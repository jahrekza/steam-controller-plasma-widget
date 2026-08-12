import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation

    property int    batteryPct:  -1
    property bool   connected:   false
    property bool   charging:    false
    property bool   provisional: true
    property string lastSeen:    ""

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
            } catch(e) {
                root.connected = false
                root.batteryPct = -1
            }
            disconnectSource(source)
        }
        function poll() {
            connectSource("cat /tmp/sc-battery.json 2>/dev/null || echo '{}'")
        }
    }

    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: runner.poll()
    }

    function levelColor() {
        if (!connected || batteryPct < 0) return "#666666"
        if (batteryPct >= 20) return "#4caf50"
        if (batteryPct >= 10) return "#ff9800"
        return "#f44336"
    }

    fullRepresentation: Item {
        id: widget

        readonly property int iconSize:   40
        readonly property int gap:         6
        readonly property int battW:      20
        readonly property int battH:      44
        readonly property int termH:       5
        readonly property int border:      2
        readonly property int battRadius:  5

        implicitWidth:  iconSize + gap + battW
        implicitHeight: battH + termH

        // Controller icon — pixel-traced from original, drawn on Canvas
        Item {
            id: controllerArea
            width:  widget.iconSize
            height: widget.iconSize
            anchors.left:           parent.left
            anchors.verticalCenter: parent.verticalCenter

            Canvas {
                anchors.fill: parent
                property color tint: Qt.color(root.levelColor())
                property real  alpha: root.connected ? 1.0 : 0.35
                onTintChanged:  requestPaint()
                onAlphaChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    var sx = width  / 100
                    var sy = height / 100
                    ctx.save()
                    ctx.scale(sx, sy)

                    var c = tint
                    ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, alpha)

                    // Draw body
                    ctx.beginPath()
                    ctx.moveTo(23.2, 97.5)
                    ctx.lineTo( 6.9, 89.3); ctx.lineTo( 6.9, 58.0)
                    ctx.lineTo(10.5, 56.0); ctx.lineTo(10.5, 48.5)
                    ctx.lineTo(14.1, 46.4); ctx.lineTo(14.1, 41.4)
                    ctx.lineTo(17.6, 39.3); ctx.lineTo(17.6, 34.2)
                    ctx.lineTo(21.2, 32.1); ctx.lineTo(24.8, 24.7)
                    ctx.lineTo(33.5, 18.9); ctx.lineTo(51.8, 16.5)
                    ctx.lineTo(54.9, 14.1); ctx.lineTo(91.1, 14.1)
                    ctx.lineTo(96.2, 17.6); ctx.lineTo(96.2, 79.8)
                    ctx.lineTo(91.1, 83.2); ctx.lineTo(54.9, 83.2)
                    ctx.lineTo(33.9, 95.1); ctx.lineTo(26.3, 95.1)
                    ctx.closePath()
                    ctx.fill()

                    // Cut out holes using destination-out compositing
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.fillStyle = "black"

                    ctx.beginPath()
                    ctx.moveTo(66.3, 73.5)
                    ctx.lineTo(71.2, 67.9); ctx.lineTo(71.2, 58.0)
                    ctx.lineTo(46.2, 58.0); ctx.lineTo(46.2, 70.2)
                    ctx.lineTo(54.9, 73.7)
                    ctx.closePath()
                    ctx.fill()

                    ctx.beginPath()
                    ctx.moveTo(66.3, 44.9)
                    ctx.lineTo(71.2, 36.6); ctx.lineTo(62.5, 30.8)
                    ctx.lineTo(51.3, 30.8); ctx.lineTo(46.2, 34.2)
                    ctx.lineTo(46.2, 41.7); ctx.lineTo(51.3, 45.1)
                    ctx.closePath()
                    ctx.fill()

                    ctx.globalCompositeOperation = "source-over"
                    ctx.restore()
                }
            }

            // Provisional/calibrating dot
            Rectangle {
                visible: root.connected && root.provisional
                width: 5; height: 5; radius: 2.5
                color: "#ff9800"
                anchors.right: parent.right
                anchors.top:   parent.top

                SequentialAnimation on opacity {
                    running: root.provisional && root.connected
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.15; duration: 900 }
                    NumberAnimation { to: 1.0;  duration: 900 }
                }
            }
        }

        // Battery section
        Item {
            id: batterySection
            width:  widget.battW
            height: widget.battH + widget.termH
            anchors.left:           controllerArea.right
            anchors.leftMargin:     widget.gap
            anchors.verticalCenter: parent.verticalCenter

            // Glow ring
            Rectangle {
                anchors.centerIn: batteryBody
                width:  batteryBody.width  + 6
                height: batteryBody.height + 6
                radius: widget.battRadius + 3
                color: "transparent"
                border.color: Qt.alpha(root.levelColor(), 0.25)
                border.width: 3
            }

            // Terminal bump
            Rectangle {
                width:  widget.battW * 0.45
                height: widget.termH
                radius: 2
                anchors.horizontalCenter: batteryBody.horizontalCenter
                anchors.bottom: batteryBody.top
                anchors.bottomMargin: -1
                color: "#888888"
            }

            // Battery body
            Rectangle {
                id: batteryBody
                width:  widget.battW
                height: widget.battH
                radius: widget.battRadius
                anchors.bottom: parent.bottom
                color: "#1e1e1e"
                border.color: "#555555"
                border.width: widget.border
                clip: true

                Rectangle {
                    id: fillRect
                    width:  parent.width  - widget.border * 2
                    height: root.connected && root.batteryPct >= 0
                            ? Math.max(widget.battRadius * 2,
                              (parent.height - widget.border * 2) * root.batteryPct / 100)
                            : 0
                    anchors.bottom:           parent.bottom
                    anchors.bottomMargin:     widget.border
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: widget.battRadius - widget.border
                    color:  root.levelColor()
                    opacity: 0.85

                    Behavior on height { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                    Behavior on color  { ColorAnimation  { duration: 400 } }
                }

                PC3.Label {
                    visible: root.charging
                    text: "⚡"
                    font.pixelSize: 12
                    anchors.centerIn: parent
                    opacity: 0.9
                }

                PC3.Label {
                    visible: !root.charging && root.connected && root.batteryPct >= 0
                    text: root.batteryPct + "%"
                    font.pixelSize: 8
                    font.bold: true
                    color: "white"
                    style: Text.Raised
                    styleColor: "#00000099"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                }
            }
        }
    }
}
