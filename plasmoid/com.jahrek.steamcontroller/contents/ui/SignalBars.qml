import QtQuick
import org.kde.kirigami as Kirigami

// Four rising bars, like a phone's signal meter; `level` (1-4) of them lit
Item {
    id: bars
    property int level: 0
    property color color: Kirigami.Theme.textColor
    property real barWidth: 2.5
    readonly property real gap: barWidth * 0.6

    implicitWidth: barWidth * 4 + gap * 3
    implicitHeight: 10

    Repeater {
        model: 4
        Rectangle {
            required property int index
            x: index * (bars.barWidth + bars.gap)
            width: bars.barWidth
            height: Math.round(bars.height * (index + 1) / 4)
            anchors.bottom: parent.bottom
            radius: bars.barWidth * 0.3
            color: bars.color
            opacity: index < bars.level ? 1 : 0.25
        }
    }
}
