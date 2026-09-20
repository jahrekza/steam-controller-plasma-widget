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
| [`plasmoid/com.jahrek.steamcontroller/`](plasmoid/com.jahrek.steamcontroller) | KDE Plasma 6 widget (QML) that renders a battery icon in the panel |
| [`plasmoid/.../contents/code/sc_battery_daemon.py`](plasmoid/com.jahrek.steamcontroller/contents/code/sc_battery_daemon.py) | Python daemon bundled inside the widget: reads `/dev/hidraw*`, finds the controller by VID:PID, writes battery/connection state to `$XDG_RUNTIME_DIR/sc-battery.json`. The widget starts it automatically. |
| [`install.sh`](install.sh) | Installs the widget for the current user (alternative to the KDE Store) |
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

**From the KDE Store:** right-click panel → *Add Widgets* → *Get New Widgets* →
search "Steam Controller Battery" (version **0.2 or newer** — 0.1 shipped without
the daemon and shows a grey icon).

**From git:**

```bash
git clone https://github.com/jahrekza/steam-controller-plasma-widget.git
cd steam-controller-plasma-widget
./install.sh
```

Either way the widget is self-contained: it launches the bundled daemon itself
(single instance, guarded by a lock file) and restarts it if it dies. No
autostart entry or separate service needed. `setsid` (util-linux) and
`python3` must be on `PATH`.

Then add the widget: **right-click desktop/panel → Add Widgets → search "Steam Controller Battery"**.

If it doesn't appear in the widget list, restart Plasma:
```bash
kquitapp6 plasmashell && kstart plasmashell
```

### Uninstall

```bash
kill "$(cat "$XDG_RUNTIME_DIR/sc-battery-daemon.lock")" 2>/dev/null
rm -rf ~/.local/share/plasma/plasmoids/com.jahrek.steamcontroller
```

If you installed v0.1, also remove its standalone daemon:
`rm ~/.local/bin/sc-battery-daemon ~/.config/autostart/sc-battery-daemon.desktop`

## How it works, in short

- Report ID `0x43` (a rare, event-driven HID report) has a byte that equals
  the battery percentage at the moment the controller connects/wakes up,
  then slowly drifts upward as a session-uptime counter (~1 unit/minute).
  The daemon captures that byte from the *first* `0x43` report of each
  connection, which gives an accurate one-shot battery reading.
- The daemon writes `$XDG_RUNTIME_DIR/sc-battery.json` (atomic rename); the
  widget polls it every 10s.
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

## Changelog

- **0.2** (2026-09-20) — daemon is now bundled inside the plasmoid and started by
  the widget; v0.1 from the KDE Store was missing it entirely and never showed a
  reading. State file moved to `$XDG_RUNTIME_DIR`. Poll interval 30s → 10s.
- **0.1** (2026-08-12) — initial release.

## Contributing

Issues and PRs welcome — especially calibration data from other controller
units/battery levels, or testing on non-Bazzite KDE Plasma distros.

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, break it, it's yours.
