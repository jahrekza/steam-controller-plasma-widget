import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Panel / system tray: symbolic controller + percentage, thin battery bar under the icon.
MouseArea {
    id: compact

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // The system tray gives every entry the same fixed, icon-sized cell and anything
    // wider spills over the neighbours: there it's the icon only (with a tiny signal
    // meter in its corner); % and dBm are in the tooltip and the popup.
    // Detected by the hint the tray gives its applets (it draws their popup headings),
    // with the plugin id as a fallback — not by one hard-coded name alone.
    readonly property bool inTray: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading)
                                   || (Plasmoid.containment !== null
                                       && Plasmoid.containment.pluginName.indexOf("systemtray") !== -1)
    // how far corner marks may stick out past the glyph: in the tray only into the cell's own margin
    readonly property real overhang: inTray ? Math.max(0, (width - glyph.w) / 2) : 1e6
    readonly property bool showText: !vertical && !inTray && root.known && root.mode !== "disconnected"
    // controller glyph: the colour picked in the settings (theme text colour by default), red when low
    readonly property color tint: root.mode === "low" ? root.colorLow : root.artColor

    Layout.minimumWidth: vertical ? 0 : row.implicitWidth
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: vertical ? glyph.height + 6 : 0

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: root.expanded = !root.expanded

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Math.round(glyph.h * 0.2)

        Item {
            id: glyph
            // 120:84 aspect, sized to the panel thickness
            // as wide as the neighbouring tray/panel icons (120:84 aspect)
            readonly property real w: Math.round(Math.min(compact.vertical ? compact.width : compact.height,
                                                          Kirigami.Units.iconSizes.smallMedium) * 1.15
                                                 * (compact.inTray ? 0.8 : 1))
            readonly property real h: Math.round(w * 84 / 120)
            Layout.preferredHeight: h
            Layout.preferredWidth: w
            height: h

            Kirigami.Icon {
                anchors.fill: parent
                roundToIconSize: false   // fill the 120:84 box instead of snapping to a 16/22 px square
                source: root.glyph
                isMask: true
                color: compact.tint
                opacity: root.mode === "disconnected" ? 0.5 : 1
            }

            // Battery bar under the icon
            Rectangle {
                visible: root.mode === "ok"
                anchors {
                    left: parent.left; right: parent.right; top: parent.bottom
                    leftMargin: parent.width * 0.2; rightMargin: parent.width * 0.2
                    topMargin: 2
                }
                height: 3; radius: 1.5
                color: root.colorTrack

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, root.batteryPct)) / 100
                    height: parent.height; radius: 1.5
                    color: root.stateColor
                }
            }

            // Tray only: a tiny signal meter in the top-right corner
            SignalBars {
                visible: compact.inTray && root.showSignalTray && root.signalLevel > 0 && root.signalStyle !== 2
                anchors { right: parent.right; top: parent.top; topMargin: -height * 0.3
                          rightMargin: -Math.min(width * 0.35, compact.overhang) }
                height: Math.round(glyph.h * 0.55)
                barWidth: Math.max(1.5, glyph.h * 0.11)
                level: root.signalLevel
                color: root.signalLevel === 1 ? root.colorLow : Kirigami.Theme.textColor
            }

            // Badge: charging bolt, or the Bluetooth logo
            Kirigami.Icon {
                visible: root.mode === "charging" || root.onBluetooth
                width: Math.max(10, Math.round(glyph.h * 0.55)); height: width
                anchors { right: parent.right; bottom: parent.bottom; bottomMargin: -height * 0.15
                          rightMargin: -Math.min(width * 0.4, compact.overhang) }
                source: root.mode === "charging" ? root.bolt : root.btLogo
                isMask: true
                color: root.stateColor
                opacity: root.pulse
            }
        }

        PC3.Label {
            visible: compact.showText
            text: root.pctText()
            font.features: { "tnum": 1 }
            color: root.mode === "low" ? root.colorLow : Kirigami.Theme.textColor
        }
        SignalIndicator {
            visible: root.showSignalTray && root.signalLevel > 0 && !compact.vertical && !compact.inTray
            Layout.alignment: Qt.AlignVCenter
            barsHeight: Math.round(glyph.h * 0.75)
            pixelSize: Kirigami.Theme.defaultFont.pixelSize
            spacing: 4
        }
    }
}
