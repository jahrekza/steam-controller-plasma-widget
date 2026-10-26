import QtQuick
import org.kde.kirigami as Kirigami

// Controller illustration: body and line art, each tinted with its configured colour.
// Double-click while the pad is connected: it shakes, the real pad rumbles, and a
// sound plays (easter egg).
Item {
    id: art
    implicitWidth: 120
    implicitHeight: 90

    Item {
        id: drawing
        anchors.fill: parent
        transformOrigin: Item.Center

        Kirigami.Icon {
            anchors.fill: parent
            roundToIconSize: false
            source: Qt.resolvedUrl("../images/steam-controller-body.svg")
            isMask: true
            color: root.artFill
        }
        Kirigami.Icon {
            anchors.fill: parent
            roundToIconSize: false
            source: Qt.resolvedUrl("../images/steam-controller-lines.svg")
            isMask: true
            color: root.artColor
        }
    }

    SequentialAnimation {
        id: shake
        loops: 2
        NumberAnimation { target: drawing; property: "rotation"; to: -7; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: drawing; property: "rotation"; to: 7;  duration: 90; easing.type: Easing.InOutQuad }
        NumberAnimation { target: drawing; property: "rotation"; to: -4; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: drawing; property: "rotation"; to: 0;  duration: 70; easing.type: Easing.OutQuad }
    }

    // every illustration (card, popup) shakes when any of them is double-clicked
    Connections {
        target: root
        function onEasterEggTickChanged() { shake.restart() }
    }

    MouseArea {
        anchors.fill: parent
        // single clicks pass through (e.g. to open the popup from the panel)
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true
        onClicked: function(mouse) { mouse.accepted = false }
        onDoubleClicked: root.easterEgg()
    }
}
