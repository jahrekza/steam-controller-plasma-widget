#!/usr/bin/env python3
"""
Steam Controller 2 battery daemon for the Plasma widget.

Reads raw HID reports from /dev/hidraw*, takes the battery % (byte[2]) and the
charging flag (byte[1]: 1 = on battery, 2 = charging) from every 0x43 report
(~every 3.5 s), and writes a JSON state file
the widget polls. Launched by the widget itself; a lock file guarantees a
single instance. Only needs Python 3 stdlib.
"""
import os, sys, json, time, select, fcntl, struct, signal, subprocess
from collections import deque
from datetime import datetime

SC_VID = 0x28de
INTERNAL_PUCK_PID = 0x1305        # receiver built into the Steam Machine
RECEIVER_PIDS = (0x1304, INTERNAL_PUCK_PID)  # standalone puck, Steam Machine
SC_PIDS = RECEIVER_PIDS + (0x1302, 0x1303)  # + controller on a USB-C cable, Bluetooth LE
HIDIOCGRAWINFO = 0x80084803
HIDIOCSFEATURE_64 = (3 << 30) | (64 << 16) | (ord("H") << 8) | 0x06
HIDIOCGFEATURE_65 = (3 << 30) | (65 << 16) | (ord("H") << 8) | 0x07
SIGNAL_WINDOW = 6           # 0x7b readings averaged for the signal strength (~2-3 s)
SIGNAL_STALE = 10           # s without a reading -> no signal value (e.g. Bluetooth has none)
DOCK_POLL = 3               # s between "is the pad on the dock?" queries

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
STATE_FILE  = os.path.join(RUNTIME_DIR, "sc-battery.json")
LOCK_FILE   = os.path.join(RUNTIME_DIR, "sc-battery-daemon.lock")


def plasmoid_version():
    """Version of the plasmoid this daemon was shipped in (its metadata.json)."""
    try:
        meta = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "metadata.json")
        with open(meta) as f:
            return json.load(f)["KPlugin"]["Version"]
    except (OSError, ValueError, KeyError):
        return ""


# Lets the widget spot a daemon left running from an older version after an
# update (the lock file keeps a new one from starting) and restart it.
DAEMON_VERSION = plasmoid_version()

# Is the pad on the puck's charging dock? Silence alone can't tell (an idle pad
# that switched itself off is silent too), but the puck can: asked with command
# 0xB4 (link state), its dock interface (the one without OUTPUT reports) answers
# 2 while a pad sits on it, 1 otherwise -- whether the pad is awake or not.
SILENCE_DISCONNECT = 2      # s without reports -> pad is off (awake it streams ~250 reports/s)
WRITE_INTERVAL = 5          # s between state file writes


def single_instance():
    fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)  # another instance already running
    os.ftruncate(fd, 0)
    os.write(fd, str(os.getpid()).encode())
    return fd  # keep open for the lifetime of the process


def hid_info(dev):
    """(connection, bluetooth MAC or "") from the hidraw node's sysfs uevent."""
    name, bus, pid, uniq = "", "", 0, ""
    try:
        with open(f"/sys/class/hidraw/{os.path.basename(dev)}/device/uevent") as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k == "HID_NAME":
                    name = v
                elif k == "HID_ID":
                    parts = v.split(":")
                    bus = parts[0]
                    pid = int(parts[2], 16) if len(parts) == 3 else 0
                elif k == "HID_UNIQ":
                    uniq = v
    except OSError:
        pass
    if bus == "0005":
        return "bluetooth", uniq
    if pid in RECEIVER_PIDS or "puck" in name.lower():
        return "receiver", ""
    return "usb", ""


def hid_pid(dev):
    """USB/BT product ID of a hidraw node, from its sysfs uevent (0 if unknown)."""
    try:
        with open(f"/sys/class/hidraw/{os.path.basename(dev)}/device/uevent") as f:
            for line in f:
                if line.startswith("HID_ID="):
                    return int(line.strip().split(":")[2], 16)
    except (OSError, IndexError, ValueError):
        pass
    return 0


def bluez_battery(address):
    """Live battery % from the BLE Battery Service via BlueZ, or None."""
    if not address:
        return None
    dev = "dev_" + address.upper().replace(":", "_")
    for hci in ("hci0", "hci1", "hci2"):
        try:
            out = subprocess.run(
                ["busctl", "--system", "get-property", "org.bluez",
                 f"/org/bluez/{hci}/{dev}", "org.bluez.Battery1", "Percentage"],
                capture_output=True, text=True, timeout=3).stdout.split()
        except (OSError, subprocess.TimeoutExpired):
            return None
        if len(out) == 2 and out[0] == "y":
            return max(0, min(100, int(out[1])))
    return None


def puck_dock_node():
    """hidraw node of the puck's dock interface: a 28de:1304 node without OUTPUT reports."""
    for i in range(32):
        base = f"/sys/class/hidraw/hidraw{i}/device"
        try:
            with open(base + "/uevent") as f:
                if "28DE:00001304" not in f.read().upper():
                    continue
            with open(base + "/report_descriptor", "rb") as f:
                desc = f.read()
        except OSError:
            continue
        j, has_out = 0, False
        while j < len(desc):
            b = desc[j]
            if b == 0xFE:                      # long item
                j += 3 + (desc[j + 1] if j + 1 < len(desc) else 0)
                continue
            if (b & 0xFC) == 0x90:             # Main item, tag Output
                has_out = True
                break
            j += 1 + (0, 1, 2, 4)[b & 3]
        if not has_out:
            return f"/dev/hidraw{i}"
    return None


def puck_docked():
    """True/False = pad on/off the puck's dock, None = can't tell (no puck, no access)."""
    dev = puck_dock_node()
    if not dev:
        return None
    try:
        fd = os.open(dev, os.O_RDWR)
    except OSError:
        return None
    try:
        out = bytearray(64)
        out[0], out[1] = 0x02, 0xB4
        fcntl.ioctl(fd, HIDIOCSFEATURE_64, bytes(out))
        time.sleep(0.05)
        buf = bytearray(65)
        buf[0] = 0x02
        fcntl.ioctl(fd, HIDIOCGFEATURE_65, buf, True)
        if buf[1] != 0xB4:                     # answer to someone else's command (e.g. Steam)
            return None
        return buf[3] == 2
    except OSError:
        return None
    finally:
        os.close(fd)


class DockCache:
    def __init__(self):
        self.value, self.at = None, 0

    def get(self):
        if time.time() - self.at >= DOCK_POLL:
            v = puck_docked()
            self.at = time.time()
            if v is not None:
                self.value = v
        return bool(self.value)

    def reset(self):
        self.at = 0


def find_device():
    """Returns (live hidraw node or None, connection of any silent controller/puck node or "")."""
    present = ""
    for i in range(32):
        dev = f"/dev/hidraw{i}"
        try:
            fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            buf = bytearray(8)
            fcntl.ioctl(fd, HIDIOCGRAWINFO, buf, True)
            _, vendor, product = struct.unpack("ihh", bytes(buf))
            if vendor & 0xffff != SC_VID or product & 0xffff not in SC_PIDS:
                continue
            present = present or hid_info(dev)[0]
            if select.select([fd], [], [], 0.15)[0]:
                return dev, present
        except OSError:
            pass
        finally:
            os.close(fd)
    return None, present


class State:
    def __init__(self):
        self.battery_pct = -1
        self.connected = False
        self.charging = False
        self.provisional = True
        self.last_seen = ""
        self.connection = ""
        self.address = ""
        self.docked = False         # on the puck's charging dock
        self.internal = False       # linked through the Steam Machine's built-in receiver
        self.signal = None          # pad <-> receiver signal strength, dBm (receiver links only)
        self._last_write = 0
        self._last_dump = None
        self.load()

    def load(self):
        try:
            with open(STATE_FILE) as f:
                d = json.load(f)
            self.battery_pct = int(d.get("battery_pct", -1))
        except Exception:
            pass

    def write(self, force=False):
        now = time.time()
        d = {
            "battery_pct": self.battery_pct,
            "connected": self.connected,
            "charging": self.charging,
            "provisional": self.provisional,
            "last_seen": self.last_seen,
            "connection": self.connection,
            "address": self.address,
            "docked": self.docked,
            "internal": self.internal,
            "signal_dbm": self.signal,
            "daemon_version": DAEMON_VERSION,
            "updated_at": datetime.now().isoformat(timespec="seconds"),
        }
        key = (d["battery_pct"], d["connected"], d["charging"], d["provisional"], d["connection"], d["docked"], d["internal"], d["signal_dbm"])
        if not force and key == self._last_dump and now - self._last_write < WRITE_INTERVAL:
            return
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(d, f)
        os.replace(tmp, STATE_FILE)  # atomic, widget never sees a partial file
        self._last_write = now
        self._last_dump = key


def run():
    st = State()
    st.write(force=True)
    silent_since = None
    bt_polled = 0
    dock = DockCache()
    charge_flag = None
    bt_battery = False
    rssi = deque(maxlen=SIGNAL_WINDOW)
    rssi_at = 0

    while True:
        dev, present = find_device()
        if not dev:
            # Silent puck: ask it whether the pad is on the dock (charging) or off.
            # No node at all = receiver unplugged / nothing to talk to.
            st.connected = False
            st.internal = False
            st.signal = None
            st.docked = present == "receiver" and dock.get()
            if present == "receiver":
                st.charging = st.docked
                st.connection = "receiver" if st.docked else ""
            else:
                st.charging = present == "usb"
                st.connection = present
            st.address = ""
            st.provisional = True    # battery_pct is now the last known value
            st.write()
            time.sleep(1)
            continue

        try:
            fd = os.open(dev, os.O_RDONLY)
            st.connection, st.address = hid_info(dev)
            st.internal = hid_pid(dev) == INTERNAL_PUCK_PID
            bt_polled = 0
            dock.reset()
            charge_flag = None
            bt_battery = False      # BlueZ answered: it wins over 0x43 on Bluetooth
            rssi.clear()
            st.signal = None
        except OSError:
            time.sleep(1)
            continue

        try:
            while True:
                r, _, _ = select.select([fd], [], [], 1.0)
                if not r:
                    silent_since = silent_since or time.time()
                    gap = time.time() - silent_since
                    if gap >= SILENCE_DISCONNECT:
                        # Pad went quiet: rescan, so a switch to cable/Bluetooth is noticed too
                        break
                    continue

                data = os.read(fd, 64)
                # Over Bluetooth the pad exposes a real Battery Service: use it, live.
                if st.connection == "bluetooth" and time.time() - bt_polled >= 30:
                    bt_polled = time.time()
                    pct = bluez_battery(st.address)
                    bt_battery = pct is not None
                    if bt_battery:
                        st.battery_pct = pct
                        st.provisional = False
                silent_since = None
                st.connected = True
                # The dock charges the pad whatever link it uses (puck radio or Bluetooth)
                st.docked = st.connection != "usb" and dock.get()
                if data and data[0] == 0x43 and len(data) >= 2 and data[1] in (1, 2):
                    charge_flag = data[1] == 2   # dock, or a USB-C cable/charger in any mode
                if charge_flag is not None:
                    st.charging = charge_flag or st.docked
                else:
                    st.charging = st.docked or st.connection == "usb"
                st.last_seen = datetime.now().strftime("%H:%M")

                # 0x7b byte[9] = signal strength between pad and receiver, signed dBm
                # (range test 2026-10-24: -20 at the puck ... about -80 at the far end
                # of the house). 0 = no reading. Not sent over Bluetooth.
                if data and data[0] == 0x7b and len(data) >= 10 and data[9]:
                    dbm = data[9] - 256 if data[9] > 127 else data[9]
                    if -110 <= dbm <= -5:
                        rssi.append(dbm)
                        rssi_at = time.time()
                if rssi and time.time() - rssi_at < SIGNAL_STALE:
                    st.signal = round(sum(rssi) / len(rssi))
                else:
                    st.signal = None

                # byte[2] is the live battery %. (Old notes called it a rising "session
                # timer" -- that was the pad charging, before the flag in byte[1] was known.)
                if data and data[0] == 0x43 and len(data) >= 3 and data[2] <= 100 and not bt_battery:
                    st.battery_pct = data[2]
                    st.provisional = False
                st.write()
        except OSError:
            st.connected = False
            st.charging = False
            st.docked = False
            st.signal = None
            st.provisional = True
            st.write()
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
        time.sleep(1)


# Rumble (output report 0x80, layout from SDL's SDL_hidapi_steam_triton.c):
# report id, type, intensity u16, left speed u16, left gain s8, right speed u16,
# right gain s8. The pad stops on its own after ~50 ms, so it is resent every 40 ms.
RUMBLE = struct.Struct("<BBHHbHb")
# Easter egg: a scream-shaped buzz (speed, seconds) -- quick rise, hold, fade
BUZZ_PATTERN = [(30000, 0.08), (55000, 0.12), (65535, 0.45), (45000, 0.15), (25000, 0.15)]


def buzz():
    """Rumble whichever controller node is live (puck slot, Bluetooth or USB)."""
    dev, _ = find_device()
    if not dev:
        return 1
    try:
        fd = os.open(dev, os.O_WRONLY)
    except OSError:
        return 1
    try:
        for speed, secs in BUZZ_PATTERN:
            end = time.time() + secs
            while time.time() < end:
                os.write(fd, RUMBLE.pack(0x80, 0, 0, speed, 0, speed, 0))
                time.sleep(0.04)
        os.write(fd, RUMBLE.pack(0x80, 0, 0, 0, 0, 0, 0))
    except OSError:
        return 1
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--buzz"]:
        sys.exit(buzz())
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    _lock = single_instance()
    try:
        run()
    except KeyboardInterrupt:
        pass
