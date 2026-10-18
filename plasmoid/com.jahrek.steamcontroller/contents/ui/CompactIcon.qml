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
    readonly property bool showText: !vertical && root.known && root.mode !== "disconnected"
    readonly property color tint: root.mode === "low" ? root.colorLow : Kirigami.Theme.textColor

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
                                                          Kirigami.Units.iconSizes.smallMedium) * 1.15)
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

            // Badge: charging bolt, or the Bluetooth logo
            Kirigami.Icon {
                visible: root.mode === "charging" || root.onBluetooth
                width: Math.max(10, Math.round(glyph.h * 0.55)); height: width
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: -width * 0.4; bottomMargin: -height * 0.15 }
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
            color: compact.tint
        }
    }
}
