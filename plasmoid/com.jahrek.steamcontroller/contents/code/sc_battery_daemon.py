#!/usr/bin/env python3
"""
Steam Controller 2 battery daemon for the Plasma widget.

Reads raw HID reports from /dev/hidraw*, takes the battery % (byte[2]) and the
charge state (byte[1]: 1 = on battery, 2 = charging, 3 = checking the charger,
4 = fully charged; names from SDL's TritonBatteryStatus_t) from every 0x43 report
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
# Battery history for the tooltip graph: survives reboots, last 24 h, a point per 5 min
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                         "steam-controller-battery")
HISTORY_FILE = os.path.join(STATE_DIR, "history.json")
HISTORY_STEP = 300          # s between history points (plus one on every charge/link change)
HISTORY_SPAN = 24 * 3600
ETA_MIN_SPAN = 300          # s of readings, and...
ETA_MIN_DELTA = 2           # ...% of change, before a time estimate is given
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
        self.charged = False        # on power and full: the pad itself says charging is done
        self.provisional = True
        self.last_seen = ""
        self.connection = ""
        self.address = ""
        self.docked = False         # on the puck's charging dock
        self.internal = False       # linked through the Steam Machine's built-in receiver
        self.signal = None          # pad <-> receiver signal strength, dBm (receiver links only)
        self.eta_min = None         # minutes until empty (discharging) or full (charging)
        self._seg = []              # (time, %) since the charging state / link last changed
        self._seg_key = None
        self.history = load_history()
        self._hist_key = None
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

    def track(self, now):
        """Feed the time estimate and the history with the current reading."""
        live = self.connected and not self.provisional and self.battery_pct >= 0
        key = (self.charging, self.connection) if live else None
        if key != self._seg_key:
            self._seg, self._seg_key = [], key
        self.eta_min = None
        if live:
            if not self._seg or self._seg[-1][1] != self.battery_pct:
                self._seg.append((now, self.battery_pct))
            t0, p0 = self._seg[0]
            dt, dp = (now - t0) / 60, self.battery_pct - p0
            if now - t0 >= ETA_MIN_SPAN and abs(dp) >= ETA_MIN_DELTA:
                rate = dp / dt                               # % per minute
                if not self.charging and rate < 0:
                    self.eta_min = round(self.battery_pct / -rate)
                elif self.charging and rate > 0:
                    self.eta_min = round((100 - self.battery_pct) / rate)
                if self.eta_min is not None and self.eta_min > 24 * 60:
                    self.eta_min = None
            # history: a point every HISTORY_STEP, and whenever charging/link changes
            hkey = (self.charging, self.connection)
            if (not self.history or now - self.history[-1][0] >= HISTORY_STEP
                    or hkey != self._hist_key):
                self._hist_key = hkey
                self.history.append([int(now), self.battery_pct, 1 if self.charging else 0])
                self.history = [h for h in self.history if now - h[0] <= HISTORY_SPAN]
                save_history(self.history)

    def write(self, force=False):
        now = time.time()
        self.track(now)
        d = {
            "battery_pct": self.battery_pct,
            "connected": self.connected,
            "charging": self.charging,
            "charged": self.charged,
            "provisional": self.provisional,
            "last_seen": self.last_seen,
            "connection": self.connection,
            "address": self.address,
            "docked": self.docked,
            "internal": self.internal,
            "signal_dbm": self.signal,
            "eta_min": self.eta_min,
            "daemon_version": DAEMON_VERSION,
            "updated_at": datetime.now().isoformat(timespec="seconds"),
        }
        key = (d["battery_pct"], d["connected"], d["charging"], d["charged"], d["provisional"], d["connection"], d["docked"], d["internal"], d["signal_dbm"], d["eta_min"])
        if not force and key == self._last_dump and now - self._last_write < WRITE_INTERVAL:
            return
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(d, f)
        os.replace(tmp, STATE_FILE)  # atomic, widget never sees a partial file
        self._last_write = now
        self._last_dump = key


def load_history():
    try:
        with open(HISTORY_FILE) as f:
            h = json.load(f)
        cutoff = time.time() - HISTORY_SPAN
        return [x for x in h if isinstance(x, list) and len(x) == 3 and x[0] >= cutoff]
    except (OSError, ValueError):
        return []


def save_history(history):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp = HISTORY_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(history, f)
        os.replace(tmp, HISTORY_FILE)
    except OSError:
        pass


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
            st.charged = False       # unknown without reports
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
            st.charged = False
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
                if data and data[0] == 0x43 and len(data) >= 2 and data[1] in (1, 2, 3, 4):
                    charge_flag = data[1]        # dock, or a USB-C cable/charger in any mode
                if charge_flag is not None:
                    # 4 = done: still on power, but no longer charging
                    st.charging = charge_flag != 1 or st.docked
                    st.charged = charge_flag == 4
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
            st.charged = False
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


# "Find controller": short strong pulses for a few seconds
FIND_PATTERN = [(65535, 0.3), (0, 0.2)] * 6


# Find controller can also play a tune on the haptic actuators (the pad has no speaker,
# but they are audible). Output report 0x83 from SDL's MsgHapticLfoTone: id, side, gain
# dB, frequency Hz, duration ms, LFO Hz, LFO depth. Gain and LFO picked by ear on the pad;
# the notes sit around 1.3 kHz, where the actuators are loudest.
TONE = struct.Struct("<BBbHHHB")
TONE_GAIN, TONE_LFO, TONE_DEPTH = 60, 31, 20
C6, E6, F6, G6, A6 = 1047, 1319, 1397, 1568, 1760
MELODIES = {   # (Hz, ms), 0 Hz = rest
    "ticktock": [(E6, 40), (0, 460), (C6, 40), (0, 460)] * 3,
    "bird":     [(G6, 50), (A6, 50), (G6, 50), (0, 150)] * 3,
    "ringing":  ([(E6, 40), (G6, 40)] * 10 + [(0, 400)]) * 2,
    "sos":      [(E6, 100), (0, 100)] * 3 + [(0, 200)] + [(E6, 300), (0, 100)] * 3 + [(0, 200)]
                + [(E6, 100), (0, 100)] * 3,
    "alarm":    [(E6, 120), (G6, 120)] * 4,
}


def play_melody(fd, notes):
    """Plays the tune on both actuators; returns when it has finished."""
    for freq, ms in notes:
        if freq:
            for side in (0, 1):
                os.write(fd, TONE.pack(0x83, side, TONE_GAIN, freq, ms, TONE_LFO, TONE_DEPTH))
        time.sleep(ms / 1000 + 0.04)


def rumble_for(fd, speed, secs):
    end = time.time() + secs
    while time.time() < end:
        os.write(fd, RUMBLE.pack(0x80, 0, 0, speed, 0, speed, 0))
        time.sleep(0.04)


def buzz(pattern=None, melody=None, rounds=3, burst=True):
    """Rumble whichever controller node is live (puck slot, Bluetooth or USB);
    with a melody, alternate the tune and a rumble burst three times instead
    (--melody: the tune once, without rumble, to preview it in the settings)."""
    dev, _ = find_device()
    if not dev:
        return 1
    try:
        fd = os.open(dev, os.O_WRONLY)
    except OSError:
        return 1
    try:
        if melody:
            for _ in range(rounds):
                play_melody(fd, melody)
                if burst:
                    rumble_for(fd, 65535, 0.8)
                    os.write(fd, RUMBLE.pack(0x80, 0, 0, 0, 0, 0, 0))
                    time.sleep(0.4)
        else:
            for speed, secs in (pattern or BUZZ_PATTERN):
                rumble_for(fd, speed, secs)
        os.write(fd, RUMBLE.pack(0x80, 0, 0, 0, 0, 0, 0))
    except OSError:
        return 1
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--buzz"]:
        sys.exit(buzz())
    if sys.argv[1:2] == ["--melody"] and len(sys.argv) == 3 and sys.argv[2] in MELODIES:
        sys.exit(buzz(melody=MELODIES[sys.argv[2]], rounds=1, burst=False))
    if sys.argv[1:2] == ["--find"]:     # --find [MELODY]
        sys.exit(buzz(FIND_PATTERN, MELODIES.get(sys.argv[2]) if len(sys.argv) > 2 else None))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    _lock = single_instance()
    try:
        run()
    except KeyboardInterrupt:
        pass
