import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Desktop widget: controller + percentage on the left, tall battery on the right.
// Designed at 254x208; everything scales with the card when it is resized.
Item {
    id: card

    readonly property bool off: root.mode === "disconnected"
    // scale factor: 1 at the base size, grows with the card (never shrinks below 1)
    readonly property real s: Math.max(1, Math.min(width / 254, height / 208))

    Layout.minimumWidth: 254
    Layout.minimumHeight: 196
    Layout.preferredWidth: 254
    Layout.preferredHeight: 208

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    // Background: solid border when live, dashed + faded when disconnected
    Rectangle {
        anchors.fill: parent
        radius: 16 * card.s
        color: Qt.alpha(Kirigami.Theme.backgroundColor, card.off ? 0.6 : 0.92)
        border.width: card.off ? 0 : 1
        border.color: "#383d43"
    }
    Shape {
        anchors.fill: parent
        visible: card.off
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "#3a3f45"
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [4, 3]
            fillColor: "transparent"
            PathRectangle { x: 0.5; y: 0.5; width: card.width - 1; height: card.height - 1; radius: 16 * card.s }
        }
    }

    RowLayout {
        id: contentRow
        // centred group: controller column, gap, battery
        anchors {
            top: parent.top; bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            topMargin: 18 * card.s; bottomMargin: 16 * card.s
        }
        spacing: 22 * card.s
        opacity: card.off ? 0.45 : 1

        // Left column — does not stretch (nested layouts fill the width by default,
        // which pushed the battery against the card's right edge)
        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.preferredWidth: 132 * card.s
            spacing: 0

            ControllerArt {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 123 * card.s     // 120:90
                Layout.preferredHeight: 92 * card.s
            }

            Item { Layout.fillHeight: true }

            Row {
                PC3.Label {
                    id: number
                    text: root.known && !card.off ? root.batteryPct : "—"
                    font.pixelSize: 30 * card.s
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    lineHeight: 1
                    color: root.mode === "low" ? root.colorLow : Kirigami.Theme.textColor
                }
                PC3.Label {
                    visible: root.known && !card.off
                    anchors.baseline: number.baseline
                    text: "%"
                    font.pixelSize: 16 * card.s
                    font.weight: Font.Medium
                    color: root.mode === "low" ? root.colorLow : Kirigami.Theme.disabledTextColor
                }
            }

            RowLayout {
                Layout.topMargin: 2 * card.s
                spacing: (root.mode === "charging" ? 4 : 6) * card.s

                Rectangle {
                    visible: root.mode === "ok" && !root.onBluetooth
                    implicitWidth: 7 * card.s; implicitHeight: implicitWidth; radius: implicitWidth / 2
                    color: root.stateColor
                }
                Kirigami.Icon {
                    visible: root.onBluetooth && root.mode !== "charging"
                    implicitWidth: 13 * card.s; implicitHeight: implicitWidth
                    roundToIconSize: false
                    source: root.btLogo
                    isMask: true
                    color: root.stateColor
                }
                Kirigami.Icon {
                    visible: root.mode === "charging"
                    implicitWidth: 12 * card.s; implicitHeight: implicitWidth
                    roundToIconSize: false
                    source: root.bolt
                    isMask: true
                    color: root.stateColor
                    opacity: root.pulse
                }
                PC3.Label {
                    // the icon next to the battery already shows the link (puck, Steam Machine,
                    // Bluetooth, USB-C), so the card keeps the status short and clear of it
                    text: root.mode === "ok"       ? i18n("Connected")
                        : root.mode === "charging" ? i18n("Charging")
                        : root.statusText()
                    font.pixelSize: 12 * card.s
                    color: card.off ? Kirigami.Theme.disabledTextColor : root.stateColor
                }
            }

            PC3.Label {
                visible: root.connected && root.internalPuck
                text: i18n("via internal puck")
                font.pixelSize: 11 * card.s
                color: Kirigami.Theme.disabledTextColor
            }

            // own line, so it never runs into the Steam Machine drawing next to the battery
            SignalIndicator {
                visible: root.showSignalCard && root.signalLevel > 0
                Layout.topMargin: 3 * card.s
                barsHeight: 12 * card.s
                barWidth: 3 * card.s
                pixelSize: 12 * card.s
                spacing: 6 * card.s
            }
        }

        // Right column — vertical battery filling the card height
        ColumnLayout {
            id: batteryColumn
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.preferredWidth: 58 * card.s
            spacing: 3 * card.s

            Rectangle {   // nub
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 22 * card.s; implicitHeight: 5 * card.s
                topLeftRadius: 2 * card.s; topRightRadius: 2 * card.s
                color: root.colorOutline
            }

            Rectangle {   // body
                id: body
                Layout.fillHeight: true
                Layout.preferredWidth: 58 * card.s
                radius: 12 * card.s
                color: "transparent"
                border.width: 2 * card.s
                border.color: root.colorOutline

                Rectangle {
                    readonly property real inset: 5 * card.s
                    readonly property real full: body.height - 2 * inset
                    visible: root.known && !card.off
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                        margins: inset
                    }
                    height: full * Math.max(0, Math.min(100, root.batteryPct)) / 100
                    radius: 7 * card.s
                    color: root.stateColor
                    opacity: root.pulse

                    Behavior on height { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                    Behavior on color  { ColorAnimation  { duration: 400 } }
                }

                Kirigami.Icon {
                    visible: root.mode === "charging"
                    anchors.centerIn: parent
                    implicitWidth: 18 * card.s; implicitHeight: implicitWidth
                    roundToIconSize: false
                    source: root.bolt
                    isMask: true
                    color: root.boltOnFill
                }
            }
        }

    }

    // How the pad is linked, in the free corner next to the battery: Steam Machine
    // (built-in receiver), standalone puck (also when docked on it), Bluetooth or USB-C
    Kirigami.Icon {
        visible: root.connected || (root.connection === "receiver" && root.docked)
        width: 50 * card.s; height: width
        // just left of the battery, bottom-aligned with the status lines
        x: contentRow.x + batteryColumn.x - width - 10 * card.s
        y: contentRow.y + contentRow.height - height
        roundToIconSize: false
        source: root.connection === "bluetooth" ? root.btLogo
              : root.connection === "usb"       ? root.usbC
              : root.internalPuck ? root.steamMachine : root.puckIcon
        isMask: true
        color: Kirigami.Theme.textColor
        opacity: card.off ? 0.45 : 0.9
    }
}
