import QtQuick
import org.kde.kirigami as Kirigami

// Controller illustration: dark body + line art tinted with the configured colour
Item {
    implicitWidth: 120
    implicitHeight: 90

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("../images/steam-controller-body.svg")
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
    Kirigami.Icon {
        anchors.fill: parent
        roundToIconSize: false
        source: Qt.resolvedUrl("../images/steam-controller-lines.svg")
        isMask: true
        color: root.artColor
    }
}
