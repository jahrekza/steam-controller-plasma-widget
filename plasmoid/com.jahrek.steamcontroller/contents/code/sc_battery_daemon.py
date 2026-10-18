#!/usr/bin/env python3
"""
Steam Controller 2 battery daemon for the Plasma widget.

Reads raw HID reports from /dev/hidraw*, captures battery % from the first
0x43 report after each connection (byte[2]) and the charging flag from every
0x43 (byte[1]: 1 = on battery, 2 = charging), and writes a JSON state file
the widget polls. Launched by the widget itself; a lock file guarantees a
single instance. Only needs Python 3 stdlib.
"""
import os, sys, json, time, select, fcntl, struct, signal, subprocess
from datetime import datetime

SC_VID = 0x28de
SC_PIDS = (0x1304, 0x1302, 0x1303)  # wireless receiver ("puck"), USB-C cable, Bluetooth LE
HIDIOCGRAWINFO = 0x80084803
HIDIOCSFEATURE_64 = (3 << 30) | (64 << 16) | (ord("H") << 8) | 0x06
HIDIOCGFEATURE_65 = (3 << 30) | (65 << 16) | (ord("H") << 8) | 0x07
DOCK_POLL = 3               # s between "is the pad on the dock?" queries

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
STATE_FILE  = os.path.join(RUNTIME_DIR, "sc-battery.json")
LOCK_FILE   = os.path.join(RUNTIME_DIR, "sc-battery-daemon.lock")

# Is the pad on the puck's charging dock? Silence alone can't tell (an idle pad
# that switched itself off is silent too), but the puck can: asked with command
# 0xB4 (link state), its dock interface (the one without OUTPUT reports) answers
# 2 while a pad sits on it, 1 otherwise -- whether the pad is awake or not.
SILENCE_DISCONNECT = 2      # s without reports -> pad is off (awake it streams ~250 reports/s)
SILENCE_NEW_SESSION = 120   # s without reports -> next 0x43 is a fresh session value
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
    name, bus, uniq = "", "", ""
    try:
        with open(f"/sys/class/hidraw/{os.path.basename(dev)}/device/uevent") as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k == "HID_NAME":
                    name = v
                elif k == "HID_ID":
                    bus = v.split(":")[0]
                elif k == "HID_UNIQ":
                    uniq = v
    except OSError:
        pass
    if bus == "0005":
        return "bluetooth", uniq
    if "puck" in name.lower():
        return "receiver", ""
    return "usb", ""


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
        self.session_b2 = None
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
            "updated_at": datetime.now().isoformat(timespec="seconds"),
        }
        key = (d["battery_pct"], d["connected"], d["charging"], d["provisional"], d["connection"], d["docked"])
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

    while True:
        dev, present = find_device()
        if not dev:
            # Silent puck: ask it whether the pad is on the dock (charging) or off.
            # No node at all = receiver unplugged / nothing to talk to.
            st.connected = False
            st.docked = present == "receiver" and dock.get()
            if present == "receiver":
                st.charging = st.docked
                st.connection = "receiver" if st.docked else ""
            else:
                st.charging = present == "usb"
                st.connection = present
            st.address = ""
            # A short dropout keeps the session's battery reading; a long one
            # means the next 0x43 starts a fresh session.
            silent_since = silent_since or time.time()
            if time.time() - silent_since >= SILENCE_NEW_SESSION:
                st.session_b2 = None
                st.provisional = True
            st.write()
            time.sleep(1)
            continue

        try:
            fd = os.open(dev, os.O_RDONLY)
            st.connection, st.address = hid_info(dev)
            bt_polled = 0
            dock.reset()
            charge_flag = None
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
                    if pct is not None:
                        st.battery_pct = pct
                        st.provisional = False
                        st.session_b2 = -1   # don't let the 0x43 heuristic override it
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

                if data and data[0] == 0x43 and len(data) >= 3 and st.session_b2 is None:
                    st.session_b2 = data[2]
                    st.battery_pct = max(0, min(100, data[2]))
                    st.provisional = False
                st.write()
        except OSError:
            st.connected = False
            st.charging = False
            st.docked = False
            st.session_b2 = None
            st.provisional = True
            st.write()
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
        time.sleep(1)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    _lock = single_instance()
    try:
        run()
    except KeyboardInterrupt:
        pass
