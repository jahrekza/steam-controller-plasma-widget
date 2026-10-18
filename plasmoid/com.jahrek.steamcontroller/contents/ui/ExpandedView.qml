import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Expanded popup from the panel icon.
ColumnLayout {
    id: popup

    readonly property color secondary: Kirigami.Theme.disabledTextColor

    Layout.preferredWidth: 380
    Layout.minimumWidth: 340
    spacing: 18

    // Header
    RowLayout {
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: 12

        Kirigami.Icon {
            implicitWidth: 34; implicitHeight: 24
            source: root.glyph
            isMask: true
            color: Kirigami.Theme.textColor
        }
        ColumnLayout {
            spacing: 1
            PC3.Label {
                text: i18n("Steam Controller")
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            PC3.Label {
                text: root.mode === "disconnected" || root.mode === "charging" || !root.connection
                      ? root.statusText()
                      : root.statusText() + " · " + root.connectionText()
                font.pixelSize: 12
                color: popup.secondary
            }
        }
    }

    Image {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 8
        Layout.bottomMargin: 4
        Layout.preferredWidth: 240
        Layout.preferredHeight: 168
        source: root.illustration
        sourceSize: Qt.size(240, 168)
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: root.mode === "disconnected" ? 0.45 : 1
    }

    // Battery
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            PC3.Label {
                Layout.alignment: Qt.AlignBaseline
                text: i18n("Battery")
                font.pixelSize: 13
                color: popup.secondary
            }
            Item { Layout.fillWidth: true }
            PC3.Label {
                Layout.alignment: Qt.AlignBaseline
                text: root.pctText()
                font.pixelSize: 22
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: root.mode === "low" ? root.colorLow : Kirigami.Theme.textColor
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

            Rectangle {
                width: root.known ? parent.width * Math.max(0, Math.min(100, root.batteryPct)) / 100 : 0
                height: parent.height
                radius: 4
                color: root.stateColor
                opacity: root.pulse
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
        }
    }

    // Details
    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        columns: 2
        columnSpacing: 16
        rowSpacing: 10
        uniformCellWidths: true

        PC3.Label { text: i18n("Status"); color: popup.secondary; font.pixelSize: 13 }
        PC3.Label {
            font.pixelSize: 13
            text: root.mode === "ok" || root.mode === "low" ? i18n("Discharging")
                : root.mode === "charging" ? i18n("Charging") : i18n("Disconnected")
        }

        PC3.Label { text: i18n("Connection"); color: popup.secondary; font.pixelSize: 13 }
        RowLayout {
            spacing: 4
            Kirigami.Icon {
                visible: root.connection === "bluetooth"
                implicitWidth: 14; implicitHeight: 14
                source: root.btLogo
                isMask: true
                color: root.colorBluetooth
            }
            PC3.Label { text: root.connectionText(); font.pixelSize: 13 }
        }

        PC3.Label { text: i18n("Low battery warning"); color: popup.secondary; font.pixelSize: 13 }
        PC3.Label { text: root.lowThreshold + "%"; font.pixelSize: 13 }

        PC3.Label {
            visible: root.known && (root.provisional || !root.connected)
            text: i18n("Last reading")
            color: popup.secondary
            font.pixelSize: 13
        }
        PC3.Label {
            visible: root.known && (root.provisional || !root.connected)
            text: root.lastSeen ? i18n("Last known value, %1", root.lastSeen) : i18n("Last known value")
            font.pixelSize: 13
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: 10

        PC3.Button {
            text: i18n("Settings")
            icon.name: "configure"
            onClicked: Plasmoid.internalAction("configure").trigger()
        }
        PC3.Button {
            // Only a Bluetooth link can be dropped from here; the puck has no such command.
            visible: root.connected && root.connection === "bluetooth" && root.address !== ""
            text: i18n("Disconnect")
            icon.name: "network-disconnect"
            onClicked: root.disconnect()
        }
    }
}
