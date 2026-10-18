import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // ── State from the daemon ────────────────────────────────────────────
    property int    batteryPct:  -1
    property bool   connected:   false
    property bool   charging:    false      // on a USB-C cable, or silent with the puck present (docked)
    property bool   provisional: true       // batteryPct is the last known value, not read this session
    property string lastSeen:    ""
    property string connection:  ""         // "receiver" (puck) | "usb" (USB-C cable) | "bluetooth"
    property string address:     ""         // Bluetooth MAC, if any

    // ── Derived state ────────────────────────────────────────────────────
    readonly property bool known: batteryPct >= 0
    readonly property int  lowThreshold: Plasmoid.configuration.lowThreshold
    readonly property bool isLow: connected && !charging && known && batteryPct <= lowThreshold
    // "ok" | "charging" | "low" | "disconnected"
    readonly property string mode: charging  ? "charging"
                                  : connected ? (isLow ? "low" : "ok")
                                  : "disconnected"

    readonly property bool onBluetooth: connected && connection === "bluetooth"

    readonly property bool isDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
                                   || Plasmoid.formFactor === PlasmaCore.Types.MediaCenter

    // ── Palette: one colour per way the pad is connected ─────────────────
    readonly property color colorDocked:    "#ff9a3c"   // charging on the puck
    readonly property color colorCable:     "#3ec47a"   // charging on a USB-C cable
    readonly property color colorWireless:  "#fcfcfc"   // wireless through the puck, not charging
    readonly property color colorBluetooth: "#3daee9"
    readonly property color colorLow:       "#ed4c4c"   // ≤ threshold and not charging
    readonly property color colorOutline:   "#5a6068"
    readonly property color colorTrack:     "#3a3f45"
    readonly property color stateColor: mode === "low"          ? colorLow
                                      : mode === "disconnected" ? colorOutline
                                      : mode === "charging"     ? (connection === "usb" ? colorCable : colorDocked)
                                      : connection === "bluetooth" ? colorBluetooth
                                      : colorWireless

    readonly property url illustration: Qt.resolvedUrl("../images/steam-controller.svg")
    readonly property url glyph:        Qt.resolvedUrl("../images/steam-controller-symbolic.svg")
    readonly property url bolt:         Qt.resolvedUrl("../images/bolt.svg")
    readonly property url btLogo:       Qt.resolvedUrl("../images/bluetooth.svg")

    function pctText() { return known ? batteryPct + "%" : "—" }

    function statusText() {
        switch (mode) {
        case "ok":       return i18n("Connected")
        case "low":      return i18n("Low — plug in")
        case "charging": return connection === "usb"      ? i18n("Charging · USB-C")
                              : connection === "receiver" ? i18n("Charging · on puck")
                              : i18n("Charging")
        }
        return i18n("Disconnected")
    }

    function connectionText() {
        switch (connection) {
        case "bluetooth": return i18n("Bluetooth")
        case "usb":       return i18n("USB-C cable")
        case "receiver":  return connected ? i18n("Wireless (puck)") : i18n("Docked on puck")
        }
        return "—"
    }

    preferredRepresentation: isDesktop ? fullRepresentation : compactRepresentation
    Plasmoid.backgroundHints: isDesktop ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground
    Plasmoid.icon: "input-gamepad"
    Plasmoid.status: mode === "low" ? PlasmaCore.Types.NeedsAttentionStatus
                   : mode === "disconnected" ? PlasmaCore.Types.PassiveStatus
                   : PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("Steam Controller")
    toolTipSubText: known && mode !== "disconnected" ? pctText() + " · " + statusText() : statusText()

    compactRepresentation: CompactIcon {}
    fullRepresentation: isDesktop ? desktopCard : expandedView

    Component { id: desktopCard; DesktopCard {} }
    Component { id: expandedView; ExpandedView {} }

    // ── Data source ──────────────────────────────────────────────────────
    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            try {
                var d = JSON.parse(data["stdout"])
                root.batteryPct  = (d.battery_pct  !== undefined) ? d.battery_pct  : -1
                root.connected   = (d.connected    !== undefined) ? d.connected    : false
                root.charging    = (d.charging     !== undefined) ? d.charging     : false
                root.provisional = (d.provisional  !== undefined) ? d.provisional  : true
                root.lastSeen    = (d.last_seen    !== undefined) ? d.last_seen    : ""
                root.connection  = (d.connection   !== undefined) ? d.connection   : ""
                root.address     = (d.address      !== undefined) ? d.address      : ""
            } catch(e) {
                root.connected = false
                root.batteryPct = -1
            }
            disconnectSource(source)
        }
        function poll() {
            connectSource("cat \"${XDG_RUNTIME_DIR:-/tmp}/sc-battery.json\" 2>/dev/null || echo '{}'")
        }
    }

    // Daemon bundled in the plasmoid: reads /dev/hidraw*, writes the JSON state file.
    // It holds a lock file, so re-launching it is a no-op when already running.
    readonly property string daemonPath: Qt.resolvedUrl("../code/sc_battery_daemon.py").toString().replace(/^file:\/\//, "")

    // Fire-and-forget shell commands (daemon launch, notifications, Bluetooth disconnect).
    P5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) { disconnectSource(source) }
        function run(cmd) { connectSource(cmd) }
    }

    Timer {
        // (re)start daemon on load and every 5 min in case it died
        interval: 300000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: shell.run("setsid -f python3 \"" + root.daemonPath + "\" >/dev/null 2>&1")
    }

    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: runner.poll()
    }

    function disconnect() {
        if (/^[0-9A-Fa-f:]{17}$/.test(address))
            shell.run("bluetoothctl disconnect " + address)
    }

    // ── Low battery notification (once per drop below the threshold) ────
    property bool lowNotified: false
    onIsLowChanged: {
        if (!isLow) {
            lowNotified = false
        } else if (Plasmoid.configuration.notifyLow && !lowNotified) {
            lowNotified = true
            shell.run("notify-send -a 'Steam Controller' -i input-gamepad -u critical '"
                      + i18n("Steam Controller battery low") + "' '"
                      + i18n("%1% left — plug it in", batteryPct) + "'")
        }
    }
}
