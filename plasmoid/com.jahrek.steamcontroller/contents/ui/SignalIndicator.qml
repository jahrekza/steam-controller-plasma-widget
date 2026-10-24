import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Signal strength as configured: bars, bars + dBm, or dBm only
RowLayout {
    id: indicator
    property real barsHeight: 10
    property real barWidth: 2.5
    property int pixelSize: 11

    readonly property color tone: root.signalLevel === 1 ? root.colorLow : Kirigami.Theme.textColor
    visible: root.signalLevel > 0
    spacing: 5

    SignalBars {
        visible: root.signalStyle !== 2
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredHeight: indicator.barsHeight
        Layout.preferredWidth: implicitWidth
        barWidth: indicator.barWidth
        level: root.signalLevel
        color: indicator.tone
    }
    PC3.Label {
        visible: root.signalStyle !== 0
        text: i18n("%1 dBm", root.signalDbm)
        font.pixelSize: indicator.pixelSize
        font.features: { "tnum": 1 }
        color: root.signalStyle === 2 ? indicator.tone : Kirigami.Theme.disabledTextColor
    }
}
