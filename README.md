# Steam Controller 2 — Battery Widget for KDE Plasma

A background daemon + KDE Plasma 6 widget that shows the battery level and
connection status of the Steam Controller 2 ("Triton", released May 2026) on
Linux — reverse-engineered from its raw HID protocol, since the Linux kernel's
`hid-steam` driver doesn't support this controller yet (see below).

![status](https://img.shields.io/badge/status-working%20prototype-yellow)

## Why this exists

The Steam Controller 2 (VID:PID `28de:1304`) is not recognized by the kernel's
`hid-steam.c` driver — it falls back to generic `hid-generic`, which means:

- Nothing shows up under `/sys/class/power_supply/`
- `upower -e` shows no controller device
- There is no standard way to read the battery level

This project reads the raw HID report stream directly from `/dev/hidraw*`,
decodes the (fully undocumented, vendor-proprietary) battery field, and
exposes it to a small KDE Plasma widget.

Full reverse-engineering notes, including how the battery byte was found and
several dead ends that were ruled out, are in [PROTOCOL_NOTES.md](PROTOCOL_NOTES.md).

## What's included

| Path | What it is |
|---|---|
| [`daemon/sc-battery-daemon`](daemon/sc-battery-daemon) | Python daemon: reads `/dev/hidraw*`, finds the controller by VID:PID, writes battery/connection state to `/tmp/sc-battery.json` |
| [`plasmoid/com.jahrek.steamcontroller/`](plasmoid/com.jahrek.steamcontroller) | KDE Plasma 6 widget (QML) that polls the JSON file and renders a battery icon in the panel |
| [`install.sh`](install.sh) | Installs both for the current user |
| `sc_dump.py`, `sc_monitor.py`, `sc_filter.py`, `sc_charge_monitor.py` | Diagnostic/research tools used to reverse-engineer the protocol (not needed just to use the widget) |
| [`PROTOCOL_NOTES.md`](PROTOCOL_NOTES.md) | Detailed HID protocol research notes |

## Status

This is a **working prototype** running on the author's own machine (Bazzite
Linux / KDE Plasma 6.7), not a polished, widely-tested release. Expect rough
edges. Tested only with one controller unit on one system.

## Requirements

- Linux with KDE Plasma 6
- Python 3 (no extra packages needed — uses only the standard library)
- udev/permissions that let your user read `/dev/hidraw*` for the controller.
  On most distros this "just works" thanks to a udev rule shipped for Steam;
  if not, you may need a udev rule granting your user rw access to the
  device's hidraw nodes.

## Install

```bash
git clone https://github.com/jahrekza/steam-controller-plasma-widget.git
cd steam-controller-plasma-widget
./install.sh
```

This will:
1. Copy the daemon to `~/.local/bin/sc-battery-daemon` and start it
2. Add an autostart entry so it starts on login
3. Copy the Plasma widget to `~/.local/share/plasma/plasmoids/com.jahrek.steamcontroller`

Then add the widget: **right-click desktop/panel → Add Widgets → search "Steam Controller Battery"**.

If it doesn't appear in the widget list, restart Plasma:
```bash
kquitapp6 plasmashell && kstart plasmashell
```

### Uninstall

```bash
rm ~/.local/bin/sc-battery-daemon
rm ~/.config/autostart/sc-battery-daemon.desktop
rm -rf ~/.local/share/plasma/plasmoids/com.jahrek.steamcontroller
pkill -f sc-battery-daemon
```

## How it works, in short

- Report ID `0x43` (a rare, event-driven HID report) has a byte that equals
  the battery percentage at the moment the controller connects/wakes up,
  then slowly drifts upward as a session-uptime counter (~1 unit/minute).
  The daemon captures that byte from the *first* `0x43` report of each
  connection, which gives an accurate one-shot battery reading.
- The daemon writes `/tmp/sc-battery.json`; the widget polls it every 30s.
- If the controller goes silent (e.g. sitting in its charging puck), the
  daemon reports it as disconnected/charging.

See [PROTOCOL_NOTES.md](PROTOCOL_NOTES.md) for the full derivation, including
two dead-end hypotheses that were ruled out with real data.

## Roadmap / next steps

- [ ] More calibration data points (currently only ~4%, ~44%, ~97% confirmed)
- [ ] Detect charging state more reliably than "went silent"
- [ ] Investigate whether a Feature Report can be used to actively query
      battery state instead of waiting for a rare passive report
- [ ] Consider upstreaming controller support to the kernel's `hid-steam.c`
      and/or contributing findings to the related
      [SDL issue](https://github.com/libsdl-org/SDL/issues/15471)

## Contributing

Issues and PRs welcome — especially calibration data from other controller
units/battery levels, or testing on non-Bazzite KDE Plasma distros.

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, break it, it's yours.
