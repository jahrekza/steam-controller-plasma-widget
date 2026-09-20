#!/usr/bin/env bash
# Installs the Steam Controller battery widget for the current user.
# The battery daemon is bundled inside the plasmoid and started by the widget itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/com.jahrek.steamcontroller"

# Clean up the standalone daemon from v0.1 installs, if present.
if [ -f "$HOME/.config/autostart/sc-battery-daemon.desktop" ]; then
    echo "==> Removing v0.1 standalone daemon + autostart entry"
    rm -f "$HOME/.config/autostart/sc-battery-daemon.desktop" "$HOME/.local/bin/sc-battery-daemon"
    pkill -f 'bin/sc-battery-daemon' 2>/dev/null || true
fi

echo "==> Installing Plasma widget to $PLASMOID_DIR"
mkdir -p "$PLASMOID_DIR"
cp -r "$SCRIPT_DIR/plasmoid/com.jahrek.steamcontroller/." "$PLASMOID_DIR/"

echo
echo "Done. Add the widget: right-click desktop/panel -> Add Widgets -> search 'Steam Controller Battery'."
echo "If it doesn't show up, restart Plasma: kquitapp6 plasmashell && kstart plasmashell"
