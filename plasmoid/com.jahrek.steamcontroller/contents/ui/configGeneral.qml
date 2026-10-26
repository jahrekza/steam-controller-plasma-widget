import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kquickcontrols as KQControls
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "../code/translations.js" as Tr
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page
    property string cfg_language
    property string cfg_languageDefault
    property string cfg_findSound
    property string cfg_findSoundDefault
    // Find controller sounds: config value, name
    readonly property var findSounds: [
        ["", tr("Vibration only")], ["ticktock", tr("Tick-tock")], ["bird", tr("Little bird")],
        ["ringing", tr("Ringing")], ["sos", tr("SOS")], ["alarm", tr("Fast alarm")]
    ]
    P5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) { disconnectSource(source) }
    }
    function playSound(name) {
        var daemon = Qt.resolvedUrl("../code/sc_battery_daemon.py").toString().replace(/^file:\/\//, "")
        // the timestamp comment makes each command unique, so it runs again on every click
        shell.connectSource("python3 \"" + daemon + "\" --melody " + name + " >/dev/null 2>&1 # " + Date.now())
    }

    // ── Copy the settings to the other copies of the widget (see main.qml) ──
    readonly property var sharedKeys: [
        "lowThreshold", "notifyLow", "notifyFull", "notifyWeakSignal", "notifyDisconnect", "findSound",
        "language", "puckName", "gabeCube", "showVia", "cardStyle", "bgColor", "glassColor", "bgOpacity",
        "pctOpacity", "illustrationColor", "illustrationFill", "elementsColor", "colorPuck",
        "colorBluetoothLed", "colorUsb", "colorDock", "colorLowBattery", "showSignalCard",
        "showSignalTray", "signalStyle"
    ]
    function shareSettings() {
        var s = {}
        for (var i = 0; i < sharedKeys.length; i++)
            s[sharedKeys[i]] = page["cfg_" + sharedKeys[i]]
        var json = JSON.stringify({ time: Date.now(), settings: s })
        var dir = "\"${XDG_STATE_HOME:-$HOME/.local/state}/steam-controller-battery\""
        shell.connectSource("mkdir -p " + dir + " && printf %s " + Qt.btoa(unescape(encodeURIComponent(json)))
                            + " | base64 -d > " + dir + "/shared-settings.tmp && mv " + dir + "/shared-settings.tmp "
                            + dir + "/shared-settings.json")
    }

    // ── The icon in the system tray: on or off, like "Disabled" in the tray's Entries ──
    property string trayState: ""      // "true" | "false" | "notray" | "" (not asked yet)
    P5Support.DataSource {
        id: trayDbus
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            var m = String(data["stdout"]).match(/string "([a-z]+)"/)
            if (m) page.trayState = m[1]
        }
        function script(js) {
            // the scripts have no single quotes, so they can be quoted for the shell as they are
            connectSource("dbus-send --session --print-reply --dest=org.kde.plasmashell /PlasmaShell "
                          + "org.kde.PlasmaShell.evaluateScript string:'" + js + "' # " + Date.now())
        }
    }
    function setTrayIcon(on) {
        trayDbus.script('var on = ON_VALUE; var id = "com.jahrek.steamcontroller"; var found = false; panels().forEach(function(p) { p.widgets("org.kde.plasma.systemtray").forEach(function(w) { w.currentConfigGroup = ["General"]; ["extraItems", "knownItems"].forEach(function(k) { var l = String(w.readConfig(k, "")).split(",").filter(function(x) { return x }); var i = l.indexOf(id); if (on && i < 0) l.push(id); if (!on && i >= 0 && k == "extraItems") l.splice(i, 1); w.writeConfig(k, l) }); w.reloadConfig(); found = true }) }); print(found ? String(on) : "notray")'.replace("ON_VALUE", on ? "true" : "false"))
    }
    Component.onCompleted: trayDbus.script('var r = "notray"; panels().forEach(function(p) { p.widgets("org.kde.plasma.systemtray").forEach(function(w) { w.currentConfigGroup = ["General"]; r = String(w.readConfig("extraItems", "")).split(",").indexOf("com.jahrek.steamcontroller") >= 0 ? "true" : "false" }) }); print(r)')

    // Translations: Plasma's i18n follows the system language; with a language picked in
    // the settings the strings come from the widget's own table instead
    function tr(s, a, b) {
        var t = Tr.lookup(cfg_language, s)
        if (t === null)
            return a === undefined ? i18n(s) : b === undefined ? i18n(s, a) : i18n(s, a, b)
        if (a !== undefined) t = t.replace("%1", a)
        if (b !== undefined) t = t.replace("%2", b)
        return t
    }
    // language names are written in their own language, so they are not translated
    readonly property var languages: [
        ["", tr("System language")], ["en", "English"], ["en_AU", "English (Australia)"],
        ["en_IE", "English (Ireland)"], ["en_SCT", "English (Scotland)"], ["cs", "Čeština"], ["da", "Dansk"],
        ["de", "Deutsch"], ["et", "Eesti"], ["es", "Español"], ["el", "Ελληνικά"], ["hr", "Hrvatski"],
        ["it", "Italiano"], ["lv", "Latviešu"], ["lt", "Lietuvių"], ["hu", "Magyar"], ["nl", "Nederlands"],
        ["nb", "Norsk bokmål"], ["pl", "Polski"], ["pt", "Português"], ["pt_BR", "Português (Brasil)"],
        ["sk", "Slovenčina"], ["fi", "Suomi"], ["sv", "Svenska"], ["tr", "Türkçe"], ["uk", "Українська"]
    ]

    property alias cfg_lowThreshold: threshold.value
    property alias cfg_notifyLow: notifyLow.checked
    property alias cfg_notifyFull: notifyFull.checked
    property alias cfg_notifyWeakSignal: notifyWeakSignal.checked
    property alias cfg_notifyDisconnect: notifyDisconnect.checked
    property bool cfg_notifyFullDefault
    property bool cfg_notifyWeakSignalDefault
    property bool cfg_notifyDisconnectDefault
    property string cfg_illustrationColor     // "" = follow the theme
    property string cfg_illustrationFill      // "" = the default dark body
    property string cfg_elementsColor         // "" = the default look
    property string cfg_illustrationFillDefault
    property string cfg_elementsColorDefault
    property alias cfg_showSignalCard: showSignalCard.checked
    property alias cfg_showVia: showVia.checked
    property bool cfg_showViaDefault
    property alias cfg_showSignalTray: showSignalTray.checked
    // defaults handed in by the config dialog (declared so it doesn't warn)
    property int cfg_lowThresholdDefault
    property bool cfg_notifyLowDefault
    property string cfg_illustrationColorDefault
    property bool cfg_showSignalCardDefault
    property bool cfg_showSignalTrayDefault
    // combos with translated items keep their value in cfg_ (not an alias to currentIndex):
    // a new language rebuilds the items, which resets currentIndex to the first one
    property int cfg_signalStyle
    property int cfg_puckName
    property int cfg_puckNameDefault
    property alias cfg_gabeCube: gabeCube.checked
    property bool cfg_gabeCubeDefault
    property int cfg_signalStyleDefault
    property int cfg_cardStyle
    property alias cfg_pctOpacity: pctOpacity.value
    property int cfg_pctOpacityDefault
    property string cfg_bgColor
    property string cfg_glassColor
    property int cfg_bgOpacity
    property string cfg_colorPuck
    property string cfg_colorBluetoothLed
    property string cfg_colorUsb
    property string cfg_colorDock
    property string cfg_colorLowBattery
    property string cfg_bgColorDefault
    property string cfg_glassColorDefault
    property int cfg_bgOpacityDefault
    property string cfg_colorPuckDefault
    property string cfg_colorBluetoothLedDefault
    property string cfg_colorUsbDefault
    property string cfg_colorDockDefault
    property string cfg_colorLowBatteryDefault
    property int cfg_cardStyleDefault

    // Appearance presets: [name, settings]; anything not listed goes back to its default
    readonly property var presets: [
        [tr("Controller LED (default)"), {}],
        [tr("Monochrome"), { colorPuck: "#fcfcfc", colorBluetoothLed: "#fcfcfc", colorUsb: "#fcfcfc",
                               colorDock: "#a1a9b1" }],
        [tr("Warm"), { cardStyle: 1, glassColor: "#2b2118", illustrationFill: "#3a2c1f",
                         illustrationColor: "#e9d9ad", elementsColor: "#e9d9ad",
                         colorPuck: "#f5e6c4", colorBluetoothLed: "#8fb8d8", colorUsb: "#9ccf7a",
                         colorDock: "#e8a050", colorLowBattery: "#e0604a" }],
        [tr("Night"), { cardStyle: 0, bgColor: "#0b0d10", illustrationFill: "#14171b",
                          illustrationColor: "#8a939c", elementsColor: "#8a939c",
                          colorPuck: "#c9d1d9", colorBluetoothLed: "#4f86b8", colorUsb: "#4f9a6c",
                          colorDock: "#b8783a", colorLowBattery: "#b84a4a", pctOpacity: 45 }]
    ]
    // every appearance setting with its default, for "Reset" and as the base of each preset
    function resetAppearance() {
        cfg_cardStyle = 0; cfg_bgColor = ""; cfg_glassColor = ""; cfg_bgOpacity = -1; cfg_pctOpacity = 60
        cfg_illustrationColor = ""; cfg_illustrationFill = ""; cfg_elementsColor = ""
        cfg_colorPuck = ""; cfg_colorBluetoothLed = ""; cfg_colorUsb = ""; cfg_colorDock = ""; cfg_colorLowBattery = ""
    }
    function applyPreset(i) {
        resetAppearance()
        var p = presets[i][1]
        for (var k in p) this["cfg_" + k] = p[k]
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: tr("Language:")
            model: page.languages.map(function(l) { return l[1] })
            currentIndex: Math.max(0, page.languages.findIndex(function(l) { return l[0] === page.cfg_language }))
            onActivated: function(i) { page.cfg_language = page.languages[i][0] }
        }
        QQC2.CheckBox {
            Kirigami.FormData.label: tr("System tray:")
            text: tr("Show an icon in the system tray")
            enabled: page.trayState === "true" || page.trayState === "false"
            checked: page.trayState === "true"
            onToggled: page.setTrayIcon(checked)
        }
        QQC2.Button {
            Kirigami.FormData.label: tr("Settings:")
            text: tr("Use these settings on the desktop and in the tray")
            icon.name: "edit-copy"
            onClicked: page.shareSettings()
        }
        QQC2.Label {
            text: tr("Both take effect right away. The copy: everything on this page goes to every copy of this widget, the desktop card and the tray icon.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }
        Item { Kirigami.FormData.isSection: true }
        QQC2.SpinBox {
            id: threshold
            Kirigami.FormData.label: tr("Low battery warning:")
            from: 5; to: 50; stepSize: 5
            textFromValue: function(value) { return value + "%" }
            valueFromText: function(text) { return parseInt(text) }
        }
        QQC2.CheckBox {
            id: notifyLow
            Kirigami.FormData.label: tr("Notify when:")
            text: tr("the battery drops below the warning level")
        }
        QQC2.CheckBox {
            id: notifyFull
            text: tr("the battery is fully charged")
        }
        QQC2.CheckBox {
            id: notifyWeakSignal
            text: tr("the signal gets weak (puck)")
        }
        QQC2.CheckBox {
            id: notifyDisconnect
            text: tr("the controller disconnects")
        }
        RowLayout {
            Kirigami.FormData.label: tr("Find controller sound:")
            QQC2.ComboBox {
                id: findSound
                model: page.findSounds.map(function(s) { return s[1] })
                currentIndex: Math.max(0, page.findSounds.findIndex(function(s) { return s[0] === page.cfg_findSound }))
                onActivated: function(i) { page.cfg_findSound = page.findSounds[i][0] }
            }
            QQC2.Button {
                icon.name: "media-playback-start"
                enabled: page.cfg_findSound !== ""
                onClicked: page.playSound(page.cfg_findSound)
                QQC2.ToolTip.text: tr("Play")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: tr("Appearance") }
        RowLayout {
            Kirigami.FormData.label: tr("Preset:")
            QQC2.ComboBox {
                id: presetBox
                model: presets.map(function(p) { return p[0] })
            }
            QQC2.Button {
                text: tr("Apply")
                icon.name: "dialog-ok-apply"
                onClicked: applyPreset(presetBox.currentIndex)
            }
        }
        QQC2.Button {
            text: tr("Reset appearance to defaults")
            icon.name: "edit-undo"
            onClicked: resetAppearance()
        }

        QQC2.CheckBox {
            id: showVia
            Kirigami.FormData.label: tr("Details:")
            text: tr("Show how it is connected or charging (via puck, Bluetooth, USB-C)")
        }
        QQC2.ComboBox {
            id: cardStyle
            currentIndex: model.length > 0 ? page.cfg_cardStyle : -1   // re-applied when the items change
            onActivated: function(i) { page.cfg_cardStyle = i }
            Kirigami.FormData.label: tr("Card background:")
            model: [tr("Dark"), tr("Glass"), tr("None (shadow only)")]
        }
        ColorChoice {
            Kirigami.FormData.label: tr("Background colour:")
            value: cfg_bgColor
            fallback: Kirigami.Theme.backgroundColor
            onPicked: function(v) { cfg_bgColor = v }
        }
        ColorChoice {
            Kirigami.FormData.label: tr("Glass colour:")
            value: cfg_glassColor
            fallback: Kirigami.Theme.backgroundColor
            onPicked: function(v) { cfg_glassColor = v }
        }
        RowLayout {
            Kirigami.FormData.label: tr("Background opacity:")
            QQC2.CheckBox {
                id: customOpacity
                text: tr("Custom")
                checked: cfg_bgOpacity >= 0
                onToggled: cfg_bgOpacity = checked ? Math.round(opacitySlider.value) : -1
            }
            QQC2.Slider {
                id: opacitySlider
                enabled: customOpacity.checked
                from: 0; to: 100; stepSize: 5
                value: cfg_bgOpacity >= 0 ? cfg_bgOpacity : (cfg_cardStyle === 1 ? 35 : 92)
                onMoved: cfg_bgOpacity = Math.round(value)
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            }
            QQC2.Label { text: Math.round(opacitySlider.value) + "%" }
        }

        RowLayout {
            Kirigami.FormData.label: tr("Percentage opacity:")
            QQC2.Slider {
                id: pctOpacity
                from: 10; to: 100; stepSize: 5
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            }
            QQC2.Label { text: Math.round(pctOpacity.value) + "%" }
        }

        ColorChoice {
            Kirigami.FormData.label: tr("Controller outline:")
            value: cfg_illustrationColor
            fallback: Kirigami.Theme.textColor
            onPicked: function(v) { cfg_illustrationColor = v }
        }
        ColorChoice {
            Kirigami.FormData.label: tr("Controller fill:")
            value: cfg_illustrationFill
            fallback: "#2c3035"
            onPicked: function(v) { cfg_illustrationFill = v }
        }
        ColorChoice {
            Kirigami.FormData.label: tr("Text and icons:")
            value: cfg_elementsColor
            fallback: Kirigami.Theme.textColor
            onPicked: function(v) { cfg_elementsColor = v }
        }
        QQC2.Label {
            text: tr("Text and icons: the %, status, signal, connection icon and battery outline. The battery fill and status mark keep the controller's LED colours, and low battery / weak signal stay red. Unticked: the default look.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: tr("Status colours") }
        ColorChoice {
            Kirigami.FormData.label: tr("Puck:")
            value: cfg_colorPuck; fallback: "#fcfcfc"
            onPicked: function(v) { cfg_colorPuck = v }
        }
        ColorChoice {
            Kirigami.FormData.label: tr("Bluetooth:")
            value: cfg_colorBluetoothLed; fallback: "#3daee9"
            onPicked: function(v) { cfg_colorBluetoothLed = v }
        }
        ColorChoice {
            Kirigami.FormData.label: tr("USB-C cable:")
            value: cfg_colorUsb; fallback: "#3ec47a"
            onPicked: function(v) { cfg_colorUsb = v }
        }
        ColorChoice {
            Kirigami.FormData.label: tr("Off, on the dock:")
            value: cfg_colorDock; fallback: "#ff9a3c"
            onPicked: function(v) { cfg_colorDock = v }
        }
        ColorChoice {
            Kirigami.FormData.label: tr("Low battery:")
            value: cfg_colorLowBattery; fallback: "#ed4c4c"
            onPicked: function(v) { cfg_colorLowBattery = v }
        }
        QQC2.Label {
            text: tr("Unticked: the colours of the controller's own LED.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showSignalCard
            Kirigami.FormData.label: tr("Signal strength:")
            text: tr("Show on the widget (desktop card)")
        }
        QQC2.CheckBox {
            id: showSignalTray
            text: tr("Show in the panel / system tray")
        }
        QQC2.ComboBox {
            id: signalStyle
            currentIndex: model.length > 0 ? page.cfg_signalStyle : -1   // re-applied when the items change
            onActivated: function(i) { page.cfg_signalStyle = i }
            Kirigami.FormData.label: tr("Show as:")
            model: [tr("Bars"), tr("Bars and dBm"), tr("dBm only")]
        }
        QQC2.Label {
            text: tr("Only for the wireless puck (also the Steam Machine's). Over Bluetooth or a cable there is no signal reading. In the system tray every entry gets a small fixed square, so there it's a tiny meter on the icon; % and dBm are in the tooltip. Placed directly on a panel, the widget shows them next to the icon.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: tr("Names") }
        QQC2.ComboBox {
            id: puckName
            currentIndex: model.length > 0 ? page.cfg_puckName : -1   // re-applied when the items change
            onActivated: function(i) { page.cfg_puckName = i }
            Kirigami.FormData.label: tr("Puck name:")
            model: [tr("Puck"), tr("Chongle"), tr("Dongle"), tr("Gizmo"), tr("Whatchamacallit")]
        }
        QQC2.CheckBox {
            id: gabeCube
            text: tr("Call the Steam Machine “GabeCube”")
        }
        QQC2.Label {
            text: tr("Chongle: what Valve called the puck internally. Dongle: what many players call it. GabeCube: the fans' nickname for the Steam Machine.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }
    }
}
