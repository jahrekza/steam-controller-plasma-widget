import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Desktop widget: controller + percentage on the left, tall battery on the right.
// Designed at 254x208; everything scales with the card when it is resized.
Item {
    id: card

    readonly property bool off: root.mode === "disconnected"
    // Embedded in the panel/tray popup: no card background of its own, and it may
    // shrink a little to fit a narrow popup
    property bool embedded: false
    // the Steam Machine drawing has room to be a bit bigger than the other link icons
    property real steamMachineSize: 53
    // The % is the last known value, not a live reading (pad off on the dock, or not
    // read yet this session): shown dimmer, with a small clock above it
    readonly property bool stale: root.known && !card.off && root.provisional
    // scale factor: 1 at the base size, grows with the card (on the desktop it never shrinks below 1)
    readonly property real s: Math.max(embedded ? 0.8 : 1, Math.min(width / 254, height / 208))
    // A card stretched wider than 254:208 gives the extra width to the left column, so
    // the battery and link icon move right and long texts get room (instead of the
    // whole group just staying centred between wider side margins)
    readonly property real extraWidth: Math.max(0, width - 254 * s)
    // Width a text line in the left column may use: the full column, or, for a line that
    // reaches down beside the link icon, only up to the icon (long translations, the ETA)
    function roomFor(item) {
        var bottom = contentRow.y + leftColumn.y + item.y + item.height
        return linkIcon.visible && bottom > linkIcon.y + 2 * s
             ? linkIcon.x - contentRow.x - leftColumn.x - 6 * s
             : leftColumn.width
    }

    implicitWidth: 254
    implicitHeight: 208
    Layout.minimumWidth: embedded ? 204 : 254
    Layout.minimumHeight: embedded ? 166 : 196

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    // Card background, from the settings: 0 dark, 1 glass (the wallpaper shows through),
    // 2 none — the content sits on the wallpaper with a soft shadow for legibility
    readonly property int bgStyle: embedded ? 0 : root.cardStyle
    layer.enabled: bgStyle === 2
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.9
        shadowBlur: 0.6
        shadowVerticalOffset: 2
    }

    // Background: solid border when live, dashed + faded when disconnected
    Rectangle {
        visible: !card.embedded && card.bgStyle !== 2
        anchors.fill: parent
        radius: 16 * card.s
        readonly property real alphaLive: root.cardBgOpacity >= 0 ? root.cardBgOpacity / 100
                                          : card.bgStyle === 1 ? 0.35 : 0.92
        color: Qt.alpha(card.bgStyle === 1 ? root.cardGlassColor : root.cardBgColor,
                        card.off ? alphaLive * 0.65 : alphaLive)
        border.width: card.off ? 0 : 1
        border.color: card.bgStyle === 1 ? Qt.rgba(1, 1, 1, 0.22) : "#383d43"
    }
    Shape {
        anchors.fill: parent
        visible: card.off && !card.embedded && card.bgStyle !== 2
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
            id: leftColumn
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.preferredWidth: 132 * card.s + card.extraWidth
            spacing: 0

            ControllerArt {
                // where it sat in the 132-wide column, also when the column grows
                Layout.alignment: Qt.AlignLeft
                Layout.leftMargin: 4.5 * card.s
                Layout.preferredWidth: 123 * card.s     // 120:90
                Layout.preferredHeight: 92 * card.s
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                id: statusRow
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
                    id: statusLabel
                    Layout.maximumWidth: card.roomFor(statusRow) - x
                    elide: Text.ElideRight
                    // the icon next to the battery already shows the link (puck, Steam Machine,
                    // Bluetooth, USB-C), so the card keeps the status short and clear of it
                    text: root.mode === "ok"       ? root.tr("Connected")
                        : root.mode === "charging" ? (root.charged ? root.tr("Charged") : root.tr("Charging"))
                        : root.statusText()
                    font.pixelSize: 12 * card.s
                    color: card.off ? Kirigami.Theme.disabledTextColor
                         : root.mode === "low" ? root.colorLow
                         : root.uiCustom ? root.uiColor : root.stateColor
                }
            }

            PC3.Label {
                id: viaLabel
                Layout.maximumWidth: card.roomFor(viaLabel)
                elide: Text.ElideRight
                // under the status (too long for one line in most languages): while charging
                // where the power comes from (the dock or a cable), otherwise how it is connected
                visible: root.showVia && (root.connected || root.mode === "charging")
                text: root.mode === "charging" ? (root.docked ? root.pk(root.tr("via puck"), root.tr("via chongle"), root.tr("via dongle"), root.tr("via the gizmo"), root.tr("via the whatchamacallit"))
                                                              : root.tr("via USB-C"))
                    : root.connection === "bluetooth" ? root.tr("via Bluetooth")
                    : root.connection === "usb"       ? root.tr("via USB-C")
                    : root.internalPuck ? root.pk(root.tr("via internal puck"), root.tr("via internal chongle"), root.tr("via internal dongle"), root.tr("via the internal gizmo"), root.tr("via the internal whatchamacallit"))
                    : root.pk(root.tr("via puck"), root.tr("via chongle"), root.tr("via dongle"), root.tr("via the gizmo"), root.tr("via the whatchamacallit"))
                font.pixelSize: 11 * card.s
                color: root.uiSecondary
            }

            // own line, so it never runs into the Steam Machine drawing next to the battery
            SignalIndicator {
                id: signalLine
                visible: root.showSignalCard && root.signalLevel > 0
                Layout.topMargin: 3 * card.s
                barsHeight: 12 * card.s
                barWidth: 3 * card.s
                pixelSize: 12 * card.s
                spacing: 6 * card.s
            }
            // time estimate: until empty, or until full while charging
            RowLayout {
                id: etaRow
                visible: root.hasEta
                Layout.topMargin: 2 * card.s
                spacing: 4 * card.s
                Kirigami.Icon { implicitWidth: 12 * card.s; implicitHeight: implicitWidth; roundToIconSize: false; source: root.hourglass; isMask: true; color: root.uiSecondary }
                PC3.Label {
                    id: etaLabel
                    // "12 h 45 min" when it fits next to the link icon, else rounded to hours
                    text: etaFull.width <= Layout.maximumWidth ? root.etaText(false) : root.etaText(true)
                    Layout.maximumWidth: card.roomFor(etaRow) - x
                    elide: Text.ElideRight
                    font.pixelSize: 12 * card.s
                    color: root.uiSecondary
                    TextMetrics { id: etaFull; font: etaLabel.font; text: root.etaText(false) }
                }
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
                color: root.uiOutline
            }

            Rectangle {   // body
                id: body
                Layout.fillHeight: true
                Layout.preferredWidth: 58 * card.s
                radius: 12 * card.s
                color: "transparent"
                border.width: 2 * card.s
                border.color: root.uiOutline

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

                // the % at the bottom of the battery, see-through (opacity from the settings);
                // on the fill, or just above it when the fill is too low to hold it
                Column {
                    id: pctBox
                    visible: root.known && !card.off
                    readonly property real fillTop: 5 * card.s + (body.height - 10 * card.s) * Math.max(0, Math.min(100, root.batteryPct)) / 100
                    readonly property bool onFill: fillTop >= pctLabel.height + 14 * card.s
                    readonly property color tone: onFill ? root.boltOnFill : root.mode === "low" ? root.colorLow : root.uiColor
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom
                              bottomMargin: onFill ? 10 * card.s : fillTop + 4 * card.s }
                    spacing: 1 * card.s
                    opacity: (card.stale ? 0.6 : 1) * root.pctOpacity / 100
                    Kirigami.Icon {
                        visible: card.stale
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: 11 * card.s; implicitHeight: implicitWidth
                        roundToIconSize: false
                        source: root.clockIcon
                        isMask: true
                        color: pctBox.tone
                    }
                    PC3.Label {
                        id: pctLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.batteryPct + "%"
                        font.pixelSize: 17 * card.s
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: pctBox.tone
                    }
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

    // Find controller: a crosshair in the top-left corner, shown while the mouse is over the card
    HoverHandler { id: cardHover }
    Kirigami.Icon {
        id: findButton
        visible: root.connected && (cardHover.hovered || findArea.pressed)
        x: 8 * card.s; y: 8 * card.s
        width: 16 * card.s; height: width
        roundToIconSize: false
        source: root.locateIcon
        isMask: true
        color: root.uiColor
        opacity: findArea.containsMouse ? 1 : 0.6
        MouseArea {
            id: findArea
            anchors.fill: parent
            anchors.margins: -4 * card.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.findController()
        }
        PC3.ToolTip.text: root.tr("Find controller")
        PC3.ToolTip.visible: findArea.containsMouse
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // How the pad is linked, in the free corner next to the battery: Steam Machine
    // (built-in receiver), standalone puck (also when docked on it), Bluetooth or USB-C
    Kirigami.Icon {
        id: linkIcon
        visible: root.connected || (root.connection === "receiver" && root.docked)
        width: (root.connected && root.internalPuck ? card.steamMachineSize : 50) * card.s; height: width
        // just left of the battery, the drawing's foot (its SVGs leave 2/24 empty below)
        // level with the battery's bottom — the same place whatever text is shown
        x: contentRow.x + batteryColumn.x - width - 10 * card.s
        y: contentRow.y + batteryColumn.y + body.y + body.height - height * 22 / 24
        roundToIconSize: false
        source: root.connection === "bluetooth" ? root.btLogo
              : root.connection === "usb"       ? root.usbC
              : root.internalPuck ? root.steamMachine : root.puckIcon
        isMask: true
        color: root.uiColor
        opacity: card.off ? 0.45 : 0.9
    }
}
