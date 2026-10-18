import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Desktop widget: controller + percentage on the left, tall battery on the right.
Item {
    id: card

    readonly property bool off: root.mode === "disconnected"

    Layout.minimumWidth: 254
    Layout.minimumHeight: 196
    Layout.preferredWidth: 254
    Layout.preferredHeight: 196

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    // Background: solid border when live, dashed + faded when disconnected
    Rectangle {
        anchors.fill: parent
        radius: 16
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
            PathRectangle { x: 0.5; y: 0.5; width: card.width - 1; height: card.height - 1; radius: 16 }
        }
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 20; rightMargin: 18
            topMargin: 18; bottomMargin: 16
        }
        spacing: 22
        opacity: card.off ? 0.45 : 1

        Item { Layout.fillWidth: true }

        // Left column — does not stretch
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 132
            spacing: 0

            Image {
                Layout.preferredWidth: 132
                Layout.preferredHeight: 92
                source: root.illustration
                sourceSize: Qt.size(132, 92)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Item { Layout.fillHeight: true }

            Row {
                PC3.Label {
                    id: number
                    text: root.known && !card.off ? root.batteryPct : "—"
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    lineHeight: 1
                    color: root.mode === "low" ? root.colorLow : Kirigami.Theme.textColor
                }
                PC3.Label {
                    visible: root.known && !card.off
                    anchors.baseline: number.baseline
                    text: "%"
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    color: root.mode === "low" ? root.colorLow : Kirigami.Theme.disabledTextColor
                }
            }

            RowLayout {
                Layout.topMargin: 2
                spacing: root.mode === "charging" ? 4 : 6

                Rectangle {
                    visible: root.mode === "ok" && !root.onBluetooth
                    implicitWidth: 7; implicitHeight: 7; radius: 3.5
                    color: root.stateColor
                }
                Kirigami.Icon {
                    visible: root.onBluetooth && root.mode !== "charging"
                    implicitWidth: 13; implicitHeight: 13
                    source: root.btLogo
                    isMask: true
                    color: root.stateColor
                }
                Kirigami.Icon {
                    visible: root.mode === "charging"
                    implicitWidth: 12; implicitHeight: 12
                    source: root.bolt
                    isMask: true
                    color: root.stateColor
                    opacity: root.pulse
                }
                PC3.Label {
                    text: root.statusText()
                    font.pixelSize: 12
                    color: card.off ? Kirigami.Theme.disabledTextColor : root.stateColor
                }
            }
        }

        // Right column — vertical battery filling the card height
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 58
            spacing: 3

            Rectangle {   // nub
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 22; implicitHeight: 5
                topLeftRadius: 2; topRightRadius: 2
                color: root.colorOutline
            }

            Rectangle {   // body
                id: body
                Layout.fillHeight: true
                Layout.preferredWidth: 58
                radius: 12
                color: "transparent"
                border.width: 2
                border.color: root.colorOutline

                Rectangle {
                    readonly property real full: body.height - 10
                    visible: root.known && !card.off
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                        margins: 5
                    }
                    height: full * Math.max(0, Math.min(100, root.batteryPct)) / 100
                    radius: 7
                    color: root.stateColor
                    opacity: root.pulse

                    Behavior on height { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                    Behavior on color  { ColorAnimation  { duration: 400 } }
                }

                Kirigami.Icon {
                    visible: root.mode === "charging"
                    anchors.centerIn: parent
                    implicitWidth: 18; implicitHeight: 18
                    source: root.bolt
                    isMask: true
                    color: root.boltOnFill
                }
            }
        }

        Item { Layout.fillWidth: true }
    }
}
