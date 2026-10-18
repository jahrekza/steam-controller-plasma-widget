#!/usr/bin/env python3
"""
Steam Controller 2 battery daemon for the Plasma widget.

Reads raw HID reports from /dev/hidraw*, captures battery % from the first
0x43 report after each connection (byte[2]), and writes a JSON state file
the widget polls. Launched by the widget itself; a lock file guarantees a
single instance. Only needs Python 3 stdlib.
"""
import os, sys, json, time, select, fcntl, struct, signal, subprocess
from datetime import datetime

SC_VID = 0x28de
SC_PIDS = (0x1304, 0x1302, 0x1303)  # wireless receiver ("puck"), USB-C cable, Bluetooth LE
HIDIOCGRAWINFO = 0x80084803

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
STATE_FILE  = os.path.join(RUNTIME_DIR, "sc-battery.json")
LOCK_FILE   = os.path.join(RUNTIME_DIR, "sc-battery-daemon.lock")

# Silence on hidraw (or no live device) = pad sitting on the charging puck or
# asleep; we can't tell them apart, so it is reported as "charging" like the
# original standalone daemon did.
SILENCE_DISCONNECT = 20     # s without reports -> treat as disconnected / docked
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
            if select.select([fd], [], [], 0.3)[0]:
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
            "updated_at": datetime.now().isoformat(timespec="seconds"),
        }
        key = (d["battery_pct"], d["connected"], d["charging"], d["provisional"], d["connection"])
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

    while True:
        dev, present = find_device()
        if not dev:
            # A silent puck node = pad docked on the puck (or asleep);
            # no node at all = receiver unplugged / nothing to talk to.
            st.connected = False
            st.charging = bool(present)
            st.connection = present
            st.address = ""
            st.session_b2 = None
            st.provisional = True
            st.write()
            time.sleep(5)
            continue

        try:
            fd = os.open(dev, os.O_RDONLY)
            st.connection, st.address = hid_info(dev)
            bt_polled = 0
        except OSError:
            time.sleep(5)
            continue

        try:
            while True:
                r, _, _ = select.select([fd], [], [], 5.0)
                if not r:
                    silent_since = silent_since or time.time()
                    gap = time.time() - silent_since
                    if gap >= SILENCE_DISCONNECT:
                        st.connected = False
                        st.charging = True
                    if gap >= SILENCE_NEW_SESSION:
                        st.session_b2 = None
                        st.provisional = True
                    st.write()
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
                # On a USB-C cable the controller is powered (and charged) by the PC.
                st.charging = st.connection == "usb"
                st.last_seen = datetime.now().strftime("%H:%M")

                if data and data[0] == 0x43 and len(data) >= 3 and st.session_b2 is None:
                    st.session_b2 = data[2]
                    st.battery_pct = max(0, min(100, data[2]))
                    st.provisional = False
                st.write()
        except OSError:
            st.connected = False
            st.charging = False
            st.session_b2 = None
            st.provisional = True
            st.write()
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
        time.sleep(3)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    _lock = single_instance()
    try:
        run()
    except KeyboardInterrupt:
        pass
