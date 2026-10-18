# Steam Controller 2 ("Triton") — HID Protocol Research Notes

**Research started:** 2026-06-12
**Last updated:** 2026-06-30
**Author:** Jahrek + Claude Sonnet 4.6
**Goal:** A KDE Plasma widget showing controller battery status

---

## 1. Device identification

| Parameter | Value |
|---|---|
| VID | `0x28de` (Valve) |
| PID | `0x1304` |
| Name | Steam Controller 2nd gen ("Triton", 2026) |
| Kernel driver | `hid-generic` (NOT `hid-steam` — that one only supports the old SC) |
| Usage page | `0xFF00` (vendor/proprietary) |
| Node | `/dev/hidraw0` (may vary; the daemon scans hidraw0-19 by VID:PID) |

**Important:** The kernel's `hid-steam.c` supports the old Steam Controller
(PID `0x1102`), but NOT the new one (PID `0x1304`). All data has to be read
directly from hidraw.

How to find the right hidraw node:
```python
import fcntl, struct
fd = os.open("/dev/hidraw0", os.O_RDWR)
buf = bytearray(8)
fcntl.ioctl(fd, 0x80084803, buf, True)   # HIDIOCGRAWINFO
_, vendor, product = struct.unpack("ihh", bytes(buf))
# vendor == 0x28de and product == 0x1304 -> this is our controller
```

---

## 2. HID report types

The `/dev/hidraw0` stream contains three report types. The first byte is
always the Report ID.

### Report ID `0x45` — main input report (~99% of the stream)

**Length:** 46 bytes
**Frequency:** ~100/s, continuous
**When:** constantly while the controller is active and off the dock

```
Offset  Size  Description
------  ----  -----------
[0]     1     Report ID = 0x45
[1]     1     Packet counter (0-255, wraps around)
[2-9]   8     Zero at rest; likely buttons/triggers (TODO)
[10]    1     IMU/gyro/accelerometer data (constantly changing)
[11]    1     Flag (1 or 2, variable)
[12]    1     IMU data
[13]    1     Flag (3-4, variable)
[14]    1     IMU data
[15]    1     Flag (1-2, variable)
[16]    1     IMU data
[17]    1     Flag (1-2, variable)
[18-29] 12    Zeros
[30-45] 16    Constant bytes, unique per device (likely device ID or calibration data)
```

Example raw hex (device at rest, 4% battery):
```
451e0000000000000000d6017c02630187020000000000000000000000004cc9f482e1009
0f39a3f0100ffffff
```

Bytes `[30-45]` are CONST for a given device:
- `4c c9 f4 82 e1 00 90 f3 9a 3f 01 00 ff ff ff ff`

### Report ID `0x7b` — event report

**Length:** 13 bytes
**Frequency:** ~1-2/minute (event-driven, not continuous)
**When:** irregular, independent of controller activity

```
Offset  Size  Description
------  ----  -----------
[0]     1     Report ID = 0x7b
[1]     1     Frame counter (varies, e.g. 245-251)
[2]     1     Constant = 0x01
[3]     1     Unknown (135-136, minimally variable)
[4-8]   5     Zeros
[9]     1     RF quality / signal strength? (216-224 at every battery level)
[10]    1     Unknown (0x00 or 0x01 at 4%, 0x00 at 50%)
[11]    1     !! TRAP: NOT battery — see "Dead ends" section
[12]    1     Constant = 0x02 (wireless mode?)
```

Example hex at ~50% battery:
```
7bf801880000000300dd003002
7bf501870000000300dd003002
```

At 4% battery (disconnected, on battery):
```
7bf801860003000500d8001602
7bf701860005000600d7001602
```

At 100% battery (after charging):
```
7bf801860005000500d8001602   <- byte[11] changes randomly, 4-78
```

### Report ID `0x43` — telemetry report ⭐

**Length:** 15 bytes
**Frequency:** ~15 out of 15000 reads (very rare, ~once/min)
**When:** sporadic, independent of activity

```
Offset  Size  Description
------  ----  -----------
[0]     1     Report ID = 0x43
[1]     1     Constant = 0x01
[2]     1     ⭐ BATTERY % at session start, then a session timer that counts up
[3]     1     Wrapping counter (fast-changing)
[4]     1     Unknown (14-16, slight correlation with battery? TODO)
[5]     1     Multiplexed sensor A (variable: 0x00, 0x28, 0x40, 0x74, 0x88...)
[6]     1     Unknown (14-16)
[7-12]  6     Zeros
[13]    1     Multiplexed sensor B (variable, see below)
[14]    1     Multiplexed sensor B' (paired with byte[13])
```

---

## 3. ⭐ The key: battery % in `0x43 byte[2]`

### Discovery (2026-06-30)

`byte[2]` of report `0x43` contains **the battery percentage at the moment
the session started**. After the connection is established, this value
slowly increments as a session timer (~1/min).

**Calibration data:**

| Battery (estimated) | byte[2] | Measured on | Notes |
|---|---|---|---|
| ~4% | **4** | 2026-06-30 14:28 | Controller drained, powered on after being idle |
| ~44% | **44** | 2026-06-12 22:56 | User estimate "around 50%" |
| ~97% | **97** | 2026-06-30 19:52 | After a full charge, ~17 min into the session |

The correlation is striking (4→4, 44→44, 97≈100) and rules out coincidence.

### Mechanism

```
byte[2] = battery_pct_at_connect + elapsed_minutes * ~1
```

On first connection (`byte[2]` read as early as possible):
```python
battery_pct = byte[2]  # approx. actual battery %
```

Over a longer session the value drifts upward. That's why the daemon
captures it on the FIRST `0x43` after each connection and stores it as
`session_b2`.

### Raw hex confirming this

**4% battery (first reports after power-on):**
```
4301 04 6c0e740e000000000000df68
          ^^ byte[2] = 0x04 = 4
```

**~44% battery:**
```
4301 2c e20e000f000000000000225c
          ^^ byte[2] = 0x2c = 44
```

**~97% battery (17 min after connecting, pad fully charged):**
```
4301 61 1c1040100000000000003867
          ^^ byte[2] = 0x61 = 97
```

---

## 4. Multiplexing in `0x43 byte[13]` — dead end #1

### What was observed

`byte[13]` and `byte[14]` rotate through several different pairs within a
single session. Each pair is likely a different hardware sensor.

**Observed pairs (byte[13], byte[14]) at different battery levels:**

| Pair (b13, b14) | hex | Seen when | Interpretation |
|---|---|---|---|
| (34, 92) | `22 5c` | 2026-06-12 ~44% | One pair seen at 44% |
| (223, 104) | `df 68` | 4% AND 100% | A constant sensor (NOT battery!) |
| (95, 98) | `5f 62` | 4% ~14:28 | External sensor |
| (149, 101) | `95 65` | 4% + at 100% after 17 min | External sensor |
| (248, 99) | `f8 63` | 4% | External sensor |
| (56, 103) | `38 67` | 4% + 100% after 8 min | External sensor |
| (139, 106) | `8b 6a` | 100%, first 8 min | Possibly a voltage sensor |
| (202, 96) | `ca 60` | 4%, rare | External sensor |

**Key observation:** `(223, 104)` shows up both at 4% AND at 100%. That
rules it out as a battery indicator — it was previously mistaken for one.

### byte[13] changes during a single session (100% battery, 2026-06-30)

```
19:35 -> 19:44  (0-8 min):    cycles(139, 223)
19:44 -> 19:52  (8-17 min):   cycles(56, 223)
19:52 ->         (17+ min):   cycles(56, 149)
```

The value in byte[13] **changes even at a constant battery level** —
confirming this is a sensor multiplexer, not a direct battery encoding.

### Linear-fit attempt (ABANDONED)

For a while we tried to identify the "battery pair" via a straight line fit:
```python
# Line through (34,92)@50% and (223,104)@4%
def battery_line(b13):
    return 92 + (b13 - 34) * (104 - 92) / (223 - 34)
```
This fit worked for 2 calibration points, but turned out to be wrong —
`(223,104)` is NOT the battery pair. Abandoned in favor of `byte[2]`.

---

## 5. `0x7b byte[11]` — dead end #2

For a while we suspected `byte[11]` in report `0x7b` was the battery
percentage.

**Why this was a false lead:**

| Time | byte[11] | Battery state |
|---|---|---|
| 14:28 (just powered on) | 48 | ~4% |
| 14:32 | 38 | ~4% (no charging!) |
| 14:35 | 20 | ~4% (drops despite no charging) |
| 19:35 (charged) | 4 | 100% (!!!) — a value LOWER than at 4% |
| 19:36 | 78 | 100% |
| 19:37 | 56, 76, 46, 64... | 100% — random oscillation |

The value oscillates between 36-78 at 100% and is LOWER at 100% than at 4%.
This is definitely NOT battery. Likely an RF packet counter, RSSI, or some
other wireless-connection indicator.

---

## 6. Other observations

### `0x43 byte[2]` as a session timer — WRONG (corrected 2026-10-18)

> **Correction:** byte[2] is the *live* battery %. The "rising" below was the pad
> charging (those sessions started right after a full charge), which wasn't
> visible before the charging flag in byte[1] was found. Evidence: over Bluetooth
> byte[2] matched the BLE Battery Service exactly (82 = 82, 83 = 83), and on the
> puck it fell 84 → 80 over an hour of play while the one-shot reading stayed at
> 84. The daemon now reads it from every `0x43`. Original (wrong) notes kept below.


After a session starts, `byte[2]` slowly rises. Rate: ~1 unit per ~1 minute.
After ~12 minutes into a session at 100% battery: byte[2] = 97 (session
started at ~85-100).

This means on long sessions the value will read higher than the actual
battery level. **Solution:** capture the FIRST `0x43` report after each
connection.

### `0x43 byte[4]` and `byte[6]`

Slight variation with battery level:
- 4% battery: `0x0e` (14) and `0x0e` (14)
- ~44% battery: `0x0e` (14) and `0x0f` (15)
- ~100% battery: `0x10` (16) and `0x10` (16)

May be an ADC reading of cell voltage (very slow change in the 20-80% range,
faster at the extremes). **TODO:** needs more data to confirm.

### `0x45 byte[30-45]` — constant per device

```
4c c9 f4 82 e1 00 90 f3 9a 3f 01 00 ff ff ff ff
```
These 16 bytes are constant throughout a session and likely for the
device's entire lifetime. Could be a unique device identifier, factory
calibration data, or a Bluetooth key.

### `0x7b byte[9]`

Stays in the 216-224 range regardless of battery or activity. Likely: RF
signal strength or connection quality (higher = better).

### Controller on the charging dock (puck)

When the controller is on the charging dock:
- `/dev/hidraw0` may still exist (BT) but stops sending `0x45` data
- `select()` returns a timeout (silence)
- The daemon interprets silence as "pad on the puck / charging"

---

## 7. Implementation architecture

### Python daemon

**Location:** `~/.local/bin/sc-battery-daemon`
**Autostart:** `~/.config/autostart/sc-battery-daemon.desktop`

**How it works:**
```
loop:
    find_sc_hidraw()          <- scans hidraw0-19 by VID:PID
    open(O_RDONLY)
    read hidraw continuously:
        0x43 -> first report: capture byte[2] as battery_pct
        every 3000 reads: write /tmp/sc-battery.json
    on IOError: reconnect
```

**JSON format at `/tmp/sc-battery.json`:**
```json
{
    "battery_pct": 97,
    "connected": true,
    "charging": false,
    "last_seen": "19:52",
    "provisional": false,
    "updated_at": "2026-06-30T19:52:56"
}
```

The file is written atomically via `rename()` to avoid partial reads in QML.

### KDE Plasma 6 widget

**Location:** `~/.local/share/plasma/plasmoids/com.jahrek.steamcontroller/`

```
com.jahrek.steamcontroller/
├── metadata.json
└── contents/
    └── ui/
        └── main.qml
```

**Plasma 6 gotchas worth knowing:**

1. `PlasmaCore.DataSource` was REMOVED in Plasma 6.
   Correct import: `import org.kde.plasma.plasma5support as P5Support`
   and `P5Support.DataSource { engine: "executable" }`

2. `metadata.json` MUST contain `"KPackageStructure": "Plasma/Applet"`.
   Without it, the widget won't show up in the widget list.

3. `kpackagetool6 --upgrade` deletes the target directory on error — it's
   safer to write files directly and restart plasmashell.

4. `XMLHttpRequest` against `file://` doesn't work inside the Plasma
   sandbox — hence `P5Support.DataSource` running `cat /tmp/sc-battery.json`.

5. Restarting plasmashell after changes:
   ```bash
   kquitapp6 plasmashell && kstart plasmashell
   ```

**Reading the JSON in QML:**
```qml
import org.kde.plasma.plasma5support as P5Support

P5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []
    onNewData: function(source, data) {
        var d = JSON.parse(data["stdout"])
        root.batteryPct = d.battery_pct ?? -1
        root.connected  = d.connected   ?? false
        disconnectSource(source)
    }
    function poll() {
        connectSource("cat /tmp/sc-battery.json 2>/dev/null || echo '{}'")
    }
}
Timer { interval: 30000; running: true; repeat: true;
        triggeredOnStart: true; onTriggered: runner.poll() }
```

---

## 8. Research tools

All in this repository's root:

| File | Description |
|---|---|
| `sc_dump.py` | Dumps the raw HID stream to a text file (hex) |
| `sc_filter.py` | Filters the stream by Report ID, counts N reports of that type |
| `sc_monitor.py` | Statistical analysis of bytes (CONST vs VARIES) for a given report |
| `sc_charge_monitor.py` | Charging monitor: logs 0x43 and 0x7b to a file, auto-reconnects |

### Usage

```bash
# Collect 15000 reports of type 0x43
python3 sc_filter.py /dev/hidraw0 15000 43

# Collect 8000 reports of type 0x7b
python3 sc_filter.py /dev/hidraw0 8000 7b

# Byte analysis of report 0x45 (8000 samples)
python3 sc_monitor.py /dev/hidraw0 45 8000

# Charging monitor (logs to sc_logs/)
python3 sc_charge_monitor.py sc_logs/my_session.txt
```

---

## 9. Calibration logs

Data collected in `sc_logs/`:

| File | Description |
|---|---|
| `sc_monitor_4pct_20260630_1428.txt` | Byte analysis of 0x45 and 0x7b at ~4% battery |
| `sc_4pct_20260630_1428.txt` | 60 reports of 0x7b at 4% — raw hex |
| `sc_43_4pct_20260630_1430.txt` | 16 reports of 0x43 at 4% — raw hex |
| `sc_45pct_20260612_2255.txt` | 20 reports of 0x7b at ~44% battery |
| `sc_monitor_50pct_20260612_2256.txt` | Byte analysis at ~44% (2 reports of 0x43) |
| `sc_charging_20260630_1510.txt` | Charging session (4% -> full), unfinished |
| `sc_100pct_20260630.txt` | Monitor at 100% — ~20 min of data, key observations |

---

## 10. Open questions / TODO

### High priority
- [ ] **What are `0x43 byte[4]` and `byte[6]`?** Are they voltage ADC
  readings? Collect data at 20%, 50%, 80%.
- [ ] **Can a Feature Report be used to actively query battery status?**
  The old SC could be "polled" via HIDIOCGFEATURE. The new one's output
  reports are unknown.
- [x] **Charging detection.** Solved 2026-10-18. The puck exposes 4 pad
  "slots" (interfaces 2-5) and a dock interface (6, the only one without OUTPUT
  reports). Feature report 2 with command `0xB4` (SET `02 b4 00…`, then GET) returns
  `02 b4 01 <state>`, state 1 = not connected, 2 = connected:

  | Pad | slot (input2) | dock (input6) |
  |---|---|---|
  | awake, wireless | 2 | 1 |
  | awake and on the dock | 2 | 2 |
  | asleep/off on the dock | 1 | 2 |
  | off, not docked | 1 | 1 |

  The dock answers 2 also when the pad is linked over Bluetooth and only
  charging on the puck (the slots then all say 1).

  The daemon polls the dock every 30 s, so "silent" is no longer assumed to mean
  "charging". Note the pad keeps streaming while docked and awake (its LED pulses
  white). Feature report 2 is a shared response buffer that Steam also uses: if
  the answer's command byte isn't `0xB4`, the daemon discards it.
- [x] **Charging flag in 0x43.** Found 2026-10-18: byte[1] of every `0x43`
  report is the charging state — `01` on battery, `02` charging — in all three
  modes (puck, Bluetooth, USB-C). It catches cases nothing else can see, e.g. a
  USB-C cable plugged in while the pad stays on Bluetooth (the pad then does
  *not* enumerate on USB; the cable only charges). `0x43` arrives every ~3.5 s over
  Bluetooth. The pad's LED follows the same logic the widget now mirrors: colour =
  link (white puck, blue Bluetooth, green USB-C), pulsing = charging, orange
  pulsing = switched off on the dock.
- [ ] **Calibration of byte[2] at low values.** Is the 4→4% mapping also
  accurate at 2%, 1%? Does the controller shut off before reaching 0?

### Lower priority
- [ ] **Decode 0x45 buttons.** Which bits correspond to A/B/X/Y, triggers,
  touchpads? See bytes [2-9], which are zero at rest.
- [ ] **0x45 byte[10-17] — IMU.** Likely gyro + accelerometer. 4 pairs
  (value, flag) — decode the format (big/little endian? signed?).
- [ ] **0x45 byte[30-45] — device ID.** Compare across different units.
- [ ] **Plasma tray icon.** A separate plasmoid type (StatusNotifierItem).
- [x] **Wired (USB) mode.** Tested 2026-10-18: on a USB-C cable the controller
      enumerates as `28de:1302` "Valve Software Steam Controller" (a single HID
      interface, `hid-generic`), not as the puck (`28de:1304`, 5 interfaces). It
      streams the same reports as over the puck: `0x42` (~250/s) and a rare `0x43`
      whose byte[2] held the battery % (0x4b → ~75–78%). The daemon matches both PIDs
      and reports `connection: "usb"` + `charging: true` for the cable.
- [x] **Bluetooth mode.** Tested 2026-10-18: the pad is a BLE HID device named
      "Steam Ctrl (BT) <serial>" with a rotating random address; once paired it
      shows up as `28de:1303` on bus `0005`. It exposes the standard **Battery
      Service** (0x180F), so BlueZ (`org.bluez.Battery1.Percentage`) and UPower
      report a live, accurate battery % — the daemon uses that instead of the
      0x43 heuristic. Pairing gotcha: after connecting, the pad requests pairing
      authorization ("Just Works"); if nobody confirms it, the pad gives up and
      powers off.
- [ ] **RF state data.** Is byte[9] in 0x7b an RSSI value? How does it
  respond to distance?
- [ ] **hid-steam.c contribution.** Eventually integrate with the kernel
  for native support.

### Unanswered questions
- **What are `0x43 byte[13]/byte[14]`?** Rotating sensors, but which
  specifically? Temperature, voltage, current? Would need power-analysis
  hardware to pin down.
- **Why is 0x43 so rare (~1/1000)?** Maybe there's a Feature Report that
  triggers it more often?
- **What is byte[12] in 0x7b (`0x02`)?** Constant — possibly a Bluetooth
  mode encoding?

---

## 11. Development environment

- **System:** Bazzite Linux (Fedora-based, immutable)
- **DE:** KDE Plasma 6.7.1
- **GPU:** RTX 4090
- **CPU:** i9-13900K
- **Path note:** `/var/home/jahrek` and `/home/jahrek` are the same inode,
  but `kpackagetool6` behaves differently depending on which is used —
  prefer `/var/home/jahrek`.

---

## 12. Research timeline

```
2026-06-12  First data collection at ~44% battery.
            2 samples of 0x43 with byte[2]=44 (0x2c).
            Wrong hypothesis: byte[13]=34 is a battery calibration value.

2026-06-30  Data collection at 4% battery.
            16 samples of 0x43 with byte[2]=4 (0x04).
            Discovery that (223,104) shows up constantly - it's NOT battery.

2026-06-30  Full charge cycle (4% -> 100%, ~4h).
            Charging monitor run during the charge.

2026-06-30  Data at 100%: byte[2]=97 (0x61).
            Breakthrough: byte[2] correlates with %! 4->4%, 44->44%, 97≈100%.
            Daemon rewritten around byte[2].
            Tests: JSON shows 97%, widget displays it correctly.
```
