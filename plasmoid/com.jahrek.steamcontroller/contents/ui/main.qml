import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "../code/translations.js" as Tr

PlasmoidItem {
    id: root

    // ── State from the daemon ────────────────────────────────────────────
    property int    batteryPct:  -1
    property bool   connected:   false
    property bool   charging:    false      // dock, USB-C cable or charger (flag from the pad itself)
    property bool   charged:     false      // still on power, but the pad says it is full
    property bool   docked:      false      // on the puck's charging dock
    property bool   internalPuck: false     // via the Steam Machine's built-in receiver
    property var    signalDbm:   null       // pad <-> receiver signal strength (receiver links only)
    property var    etaMin:      null       // minutes until empty (discharging) or full (charging)
    property bool   provisional: true       // batteryPct is the last known value, not read this session
    property string lastSeen:    ""
    property string connection:  ""         // "receiver" (puck) | "usb" (USB-C cable) | "bluetooth"

    // ── Derived state ────────────────────────────────────────────────────
    readonly property bool known: batteryPct >= 0
    readonly property int  lowThreshold: Plasmoid.configuration.lowThreshold
    readonly property bool isLow: connected && !charging && known && batteryPct <= lowThreshold
    // "ok" | "charging" | "low" | "disconnected"
    readonly property string mode: charging  ? "charging"
                                  : connected ? (isLow ? "low" : "ok")
                                  : "disconnected"

    readonly property bool onBluetooth: connected && connection === "bluetooth"

    // Signal strength as 1-4 bars (0 = no reading), thresholds from the range test
    readonly property int signalLevel: !connected || signalDbm === null ? 0
                                     : signalDbm >= -55 ? 4 : signalDbm >= -65 ? 3
                                     : signalDbm >= -75 ? 2 : 1
    readonly property bool showSignalCard: Plasmoid.configuration.showSignalCard
    readonly property bool showVia: Plasmoid.configuration.showVia   // "via puck / Bluetooth / USB-C" line
    readonly property bool showSignalTray: Plasmoid.configuration.showSignalTray
    readonly property int  signalStyle: Plasmoid.configuration.signalStyle   // 0 bars, 1 bars + dBm, 2 dBm
    readonly property string language: Plasmoid.configuration.language   // "" = the system language
    // Translations: Plasma's i18n follows the system language; with a language picked in
    // the settings the strings come from the widget's own table instead
    function tr(s, a, b) {
        var t = Tr.lookup(language, s)
        if (t === null)
            return a === undefined ? i18n(s) : b === undefined ? i18n(s, a) : i18n(s, a, b)
        if (a !== undefined) t = t.replace("%1", a)
        if (b !== undefined) t = t.replace("%2", b)
        return t
    }

    readonly property int  puckName: Plasmoid.configuration.puckName   // 0 puck, 1 chongle, 2 dongle, 3 gizmo (each language: its word for a little soap), 4 whatchamacallit
    readonly property bool gabeCube: Plasmoid.configuration.gabeCube

    // The puck under the name picked in the settings; each form is its own string so
    // every language can decline it properly
    function pk(puck, chongle, dongle, soap, whatsit) {
        return [puck, chongle, dongle, soap, whatsit][puckName] || puck
    }
    function machine(text) { return gabeCube ? text.replace("Steam Machine", "GabeCube") : text }
    readonly property int  cardStyle: Plasmoid.configuration.cardStyle       // 0 dark, 1 glass, 2 none (shadow)
    function signalText() {
        return [tr("No signal"), tr("Weak"), tr("Fair"), tr("Good"), tr("Excellent")][signalLevel]
    }

    readonly property bool isDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
                                   || Plasmoid.formFactor === PlasmaCore.Types.MediaCenter

    // ── Palette: mirrors the pad's own LED ───────────────────────────────
    // Colour = how it is connected; pulsing = charging.
    // Defaults follow the LED; each can be overridden in the settings.
    function cfgColor(value, fallback) { return value !== "" ? value : fallback }
    readonly property color colorWireless:  cfgColor(Plasmoid.configuration.colorPuck, "#fcfcfc")         // through the puck
    readonly property color colorBluetooth: cfgColor(Plasmoid.configuration.colorBluetoothLed, "#3daee9")
    readonly property color colorCable:     cfgColor(Plasmoid.configuration.colorUsb, "#3ec47a")          // USB-C cable to the PC
    readonly property color colorDocked:    cfgColor(Plasmoid.configuration.colorDock, "#ff9a3c")         // switched off, charging on the puck
    readonly property color colorLow:       cfgColor(Plasmoid.configuration.colorLowBattery, "#ed4c4c")   // ≤ threshold and not charging
    readonly property color colorOutline:   "#5a6068"
    readonly property color colorTrack:     "#3a3f45"
    // Controller illustration: the theme's text colour unless one is picked in the settings
    readonly property color artColor: Plasmoid.configuration.illustrationColor !== ""
                                      ? Plasmoid.configuration.illustrationColor : Kirigami.Theme.textColor
    readonly property color artFill: Plasmoid.configuration.illustrationFill !== ""
                                     ? Plasmoid.configuration.illustrationFill : "#2c3035"
    // One custom colour for the %, status, signal, link icon and battery outline;
    // unset, each keeps its default (text / secondary text / outline grey)
    readonly property bool  uiCustom: Plasmoid.configuration.elementsColor !== ""
    readonly property color uiColor: uiCustom ? Plasmoid.configuration.elementsColor : Kirigami.Theme.textColor
    readonly property color uiSecondary: uiCustom ? uiColor : Kirigami.Theme.disabledTextColor
    readonly property color uiOutline: uiCustom ? uiColor : colorOutline
    readonly property bool pulsing: mode === "charging" && !charged
    readonly property color stateColor: mode === "low"          ? colorLow
                                      : mode === "disconnected" ? colorOutline
                                      : !connected              ? colorDocked
                                      : connection === "usb"       ? colorCable
                                      : connection === "bluetooth" ? colorBluetooth
                                      : colorWireless
    // Bolt drawn on top of the battery fill: dark on a light fill, white on a dark one
    readonly property color boltOnFill: 0.299 * stateColor.r + 0.587 * stateColor.g + 0.114 * stateColor.b > 0.6
                                        ? "#23262a" : "#fcfcfc"
    // Card background: colour per style and an optional fixed opacity (-1 = style default)
    readonly property color cardBgColor: cfgColor(Plasmoid.configuration.bgColor, Kirigami.Theme.backgroundColor)
    readonly property color cardGlassColor: cfgColor(Plasmoid.configuration.glassColor, Kirigami.Theme.backgroundColor)
    readonly property int   cardBgOpacity: Plasmoid.configuration.bgOpacity
    readonly property int   pctOpacity: Plasmoid.configuration.pctOpacity   // the % inside the battery

    readonly property url glyph:        Qt.resolvedUrl("../images/steam-controller-symbolic.svg")
    readonly property url bolt:         Qt.resolvedUrl("../images/bolt.svg")
    readonly property url btLogo:       Qt.resolvedUrl("../images/bluetooth.svg")
    readonly property url steamMachine: Qt.resolvedUrl("../images/steam-machine.svg")
    readonly property url puckIcon:     Qt.resolvedUrl("../images/puck.svg")
    readonly property url usbC:         Qt.resolvedUrl("../images/usb-c.svg")
    readonly property url clockIcon:    Qt.resolvedUrl("../images/clock.svg")
    readonly property url hourglass:    Qt.resolvedUrl("../images/hourglass.svg")
    readonly property url locateIcon:   Qt.resolvedUrl("../images/locate.svg")

    // Breathing opacity shared by everything that pulses (1 when not pulsing)
    property real pulse: 1
    SequentialAnimation on pulse {
        running: root.pulsing
        loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 1200; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1;   duration: 1200; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.pulse = 1
    }

    function pctText() { return known ? batteryPct + "%" : "—" }

    // Time estimate: until empty, or until full while charging. Short form rounds to hours.
    readonly property bool hasEta: connected && etaMin !== null && !charged
    function etaText(short) {
        if (etaMin === null) return ""
        if (etaMin < 60) return tr("%1 min", etaMin)
        var h = Math.floor(etaMin / 60), m = etaMin % 60
        if (short) return tr("%1 h", Math.round(etaMin / 60))
        return m === 0 ? tr("%1 h", h) : tr("%1 h %2 min", h, m)
    }

    function statusText() {
        switch (mode) {
        case "ok":       return internalPuck ? pk(tr("Connected · internal puck"), tr("Connected · internal chongle"), tr("Connected · internal dongle"), tr("Connected · internal gizmo"), tr("Connected · internal whatchamacallit"))
                                            : tr("Connected")
        case "low":      return tr("Low — plug in")
        case "charging": return charged               ? tr("Fully charged")
                              : docked                ? pk(tr("Charging · on puck"), tr("Charging · on chongle"), tr("Charging · on dongle"), tr("Charging · on the gizmo"), tr("Charging · on the whatchamacallit"))
                              : connection === "usb" ? tr("Charging · USB-C")
                              : tr("Charging · cable")
        }
        return tr("Disconnected")
    }

    function connectionText() {
        switch (connection) {
        case "bluetooth": return tr("Bluetooth")
        case "usb":       return tr("USB-C cable")
        case "receiver":  return !connected ? (docked ? pk(tr("Docked on puck"), tr("Docked on chongle"), tr("Docked on dongle"), tr("Docked on the gizmo"), tr("Docked on the whatchamacallit")) : "—")
                               : internalPuck ? machine(pk(tr("Internal puck (Steam Machine)"), tr("Internal chongle (Steam Machine)"), tr("Internal dongle (Steam Machine)"), tr("Internal gizmo (Steam Machine)"), tr("Internal whatchamacallit (Steam Machine)")))
                               : pk(tr("Wireless (puck)"), tr("Wireless (chongle)"), tr("Wireless (dongle)"), tr("Wireless (gizmo)"), tr("Wireless (whatchamacallit)"))
        }
        return "—"
    }

    // On the desktop: the card. Elsewhere leave it unset — the system tray only opens
    // an applet's popup when preferredRepresentation is null — and make the switch
    // sizes unreachable, so a panel (however thick) always shows the icon + popup.
    // Plasma applies the switch sizes on the desktop too, so they must stay 0 there,
    // or the card turns into the icon.
    preferredRepresentation: isDesktop ? fullRepresentation : null
    switchWidth: isDesktop ? 0 : Kirigami.Units.gridUnit * 1000
    switchHeight: isDesktop ? 0 : Kirigami.Units.gridUnit * 1000
    Plasmoid.backgroundHints: isDesktop ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground
    Plasmoid.icon: "input-gamepad"
    Plasmoid.status: mode === "low" ? PlasmaCore.Types.NeedsAttentionStatus
                   : mode === "disconnected" ? PlasmaCore.Types.PassiveStatus
                   : PlasmaCore.Types.ActiveStatus

    toolTipMainText: tr("Steam Controller")
    // Signal in the tooltip follows the panel/tray setting and its style
    readonly property string signalTooltip: !showSignalTray || signalLevel === 0 ? ""
        : signalStyle === 0 ? tr("Signal: %1", signalText())
        : signalStyle === 1 ? tr("Signal: %1 (%2 dBm)", signalText(), signalDbm)
        : tr("Signal: %1 dBm", signalDbm)
    toolTipSubText: (known && mode !== "disconnected" ? pctText() + " · " + statusText() : statusText())
                    + (signalTooltip !== "" ? " · " + signalTooltip : "")
                    + (hasEta ? " · " + (charging ? tr("full in %1", etaText(false)) : tr("%1 left", etaText(false))) : "")
    toolTipItem: ToolTipContent {}

    // Battery history (written by the daemon) for the tooltip graph
    property var history: []
    P5Support.DataSource {
        id: historyReader
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            try { root.history = JSON.parse(data["stdout"]) } catch (e) { root.history = [] }
            disconnectSource(source)
        }
        function read() {
            connectSource("cat \"${XDG_STATE_HOME:-$HOME/.local/state}/steam-controller-battery/history.json\" 2>/dev/null || echo '[]'")
        }
    }
    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: historyReader.read()
    }

    // ── Settings shared by this widget's copies (desktop card, tray icon) ──
    // "Use these settings on the desktop and in the tray" in the settings writes them to
    // a file; every copy applies a newer file to its own configuration (also the one it
    // came from, which just gets what its dialog shows)
    property real sharedSettingsTime: -1     // -1 = not read yet: a file already there is not applied
    P5Support.DataSource {
        id: sharedReader
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            var d = null
            try { d = JSON.parse(data["stdout"]) } catch (e) {}
            if (!d || typeof d.time !== "number") {
                root.sharedSettingsTime = Math.max(root.sharedSettingsTime, 0)
                return
            }
            if (root.sharedSettingsTime >= 0 && d.time > root.sharedSettingsTime) {
                for (var k in d.settings)
                    if (Plasmoid.configuration[k] !== undefined && Plasmoid.configuration[k] !== d.settings[k])
                        Plasmoid.configuration[k] = d.settings[k]
            }
            root.sharedSettingsTime = d.time
        }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: sharedReader.connectSource("cat \"${XDG_STATE_HOME:-$HOME/.local/state}/steam-controller-battery/shared-settings.json\" 2>/dev/null || echo '{}'")
    }

    // ── Find controller: rumble it for a few seconds (right-click menu, card corner) ──
    function findController() {
        // optional tune from the settings, alternating with the rumble ("" = rumble only)
        var sound = Plasmoid.configuration.findSound
        shell.run("python3 \"" + root.daemonPath + "\" --find" + (sound ? " " + sound : "") + " >/dev/null 2>&1")
    }
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: tr("Find controller")
            icon.name: "find-location"
            enabled: root.connected
            onTriggered: root.findController()
        }
    ]

    // Desktop notification; title and body go through single quotes, so escape them
    function notify(title, body, urgency) {
        function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
        shell.run("notify-send -a 'Steam Controller' -i input-gamepad -u " + (urgency || "normal")
                  + " " + q(title) + " " + q(body))
    }

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
                root.charged     = d.charged === true
                root.provisional = (d.provisional  !== undefined) ? d.provisional  : true
                root.lastSeen    = (d.last_seen    !== undefined) ? d.last_seen    : ""
                root.connection  = (d.connection   !== undefined) ? d.connection   : ""
                root.docked      = (d.docked       !== undefined) ? d.docked       : false
                root.internalPuck = d.internal === true
                root.signalDbm   = (typeof d.signal_dbm === "number") ? d.signal_dbm : null
                root.etaMin      = (typeof d.eta_min === "number") ? d.eta_min : null
                root.checkDaemonVersion(d.daemon_version || "")
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

    // Fire-and-forget shell commands (daemon launch, notifications, easter egg).
    P5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) { disconnectSource(source) }
        function run(cmd) { connectSource(cmd) }
    }

    readonly property string startDaemon: "setsid -f python3 \"" + daemonPath + "\" >/dev/null 2>&1"

    Timer {
        // (re)start daemon on load and every 5 min in case it died
        interval: 300000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: shell.run(root.startDaemon)
    }

    // After an update (KDE Store, install.sh) the daemon of the previous version
    // keeps running and its lock file stops the new one from starting, so the
    // widget replaces it. At most once a minute, in case something keeps failing.
    property double lastDaemonRestart: 0
    function checkDaemonVersion(running) {
        const mine = Plasmoid.metaData.version
        if (!mine || running === mine || Date.now() - lastDaemonRestart < 60000)
            return
        lastDaemonRestart = Date.now()
        shell.run("kill \"$(cat \"${XDG_RUNTIME_DIR:-/tmp}/sc-battery-daemon.lock\")\" 2>/dev/null; sleep 1; "
                  + startDaemon)
    }

    Timer {
        // the daemon rewrites the file the moment something changes; reading it is a cheap `cat`
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: runner.poll()
    }

    // ── Easter egg: double-click the controller ──────────────────────────
    // The pad rumbles and a sound plays: your own file in
    // ~/.local/share/steam-controller-battery/easter-egg.* (mp3/ogg/wav/flac),
    // otherwise one shipped in the package's sounds/ folder, if any.
    property int easterEggTick: 0
    readonly property string soundsDir: Qt.resolvedUrl("../sounds").toString().replace(/^file:\/\//, "")
    function easterEgg() {
        if (!connected)
            return
        easterEggTick++
        shell.run("python3 \"" + daemonPath + "\" --buzz >/dev/null 2>&1 & "
                  + "for f in \"${XDG_DATA_HOME:-$HOME/.local/share}/steam-controller-battery/easter-egg.\"* "
                  + "\"" + soundsDir + "/easter-egg.\"*; do "
                  + "[ -f \"$f\" ] && { pw-play \"$f\" 2>/dev/null || paplay \"$f\" 2>/dev/null; break; }; done")
    }

    // ── Notifications (each once per event, re-armed when the condition clears) ──
    property bool lowNotified: false
    onIsLowChanged: {
        if (!isLow) {
            lowNotified = false
        } else if (Plasmoid.configuration.notifyLow && !lowNotified) {
            lowNotified = true
            notify(tr("Steam Controller battery low"), tr("%1% left — plug it in", batteryPct), "critical")
        }
    }

    // fully charged
    property bool fullNotified: false
    readonly property bool isFull: connected && (charged || (charging && batteryPct >= 100))
    onIsFullChanged: {
        if (isFull && Plasmoid.configuration.notifyFull && !fullNotified) {
            fullNotified = true
            notify(tr("Steam Controller charged"), tr("The battery is full."))
        }
    }
    onBatteryPctChanged: if (batteryPct < 95) fullNotified = false

    // weak signal: only after it has stayed at one bar for 10 s (no flapping)
    property bool weakNotified: false
    Timer {
        id: weakTimer
        interval: 10000
        onTriggered: if (root.signalLevel === 1 && !root.weakNotified) {
            root.weakNotified = true
            root.notify(tr("Weak controller signal"), tr("The controller is far from the receiver and may disconnect."))
        }
    }
    onSignalLevelChanged: {
        if (signalLevel === 1 && Plasmoid.configuration.notifyWeakSignal) weakTimer.restart()
        else weakTimer.stop()
        if (signalLevel >= 3) weakNotified = false
    }

    // disconnected: only if it had been connected for a while (not on start-up or a flicker)
    property double connectedSince: 0
    onConnectedChanged: {
        if (connected) {
            connectedSince = Date.now()
        } else if (Plasmoid.configuration.notifyDisconnect && connectedSince > 0
                   && Date.now() - connectedSince > 60000 && !charging) {
            notify(tr("Steam Controller disconnected"), tr("The controller is no longer connected."))
        }
    }
}
