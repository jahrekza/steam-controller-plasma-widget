#!/usr/bin/env bash
# Installs the Steam Controller battery daemon + KDE Plasma 6 widget for the current user.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="$HOME/.local/bin"
AUTOSTART_DIR="$HOME/.config/autostart"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/com.jahrek.steamcontroller"

echo "==> Installing daemon to $BIN_DIR/sc-battery-daemon"
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/daemon/sc-battery-daemon" "$BIN_DIR/sc-battery-daemon"
chmod +x "$BIN_DIR/sc-battery-daemon"

echo "==> Installing autostart entry"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/sc-battery-daemon.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Steam Controller Battery Daemon
Exec=$BIN_DIR/sc-battery-daemon
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

echo "==> Installing Plasma widget to $PLASMOID_DIR"
mkdir -p "$PLASMOID_DIR"
cp -r "$SCRIPT_DIR/plasmoid/com.jahrek.steamcontroller/." "$PLASMOID_DIR/"

echo "==> Starting daemon now (also autostarts on next login)"
pkill -f sc-battery-daemon 2>/dev/null || true
nohup "$BIN_DIR/sc-battery-daemon" >/tmp/sc-battery-daemon.log 2>&1 &
disown

echo
echo "Done. Add the widget: right-click desktop/panel -> Add Widgets -> search 'Steam Controller Battery'."
echo "If it doesn't show up, restart Plasma: kquitapp6 plasmashell && kstart plasmashell"
