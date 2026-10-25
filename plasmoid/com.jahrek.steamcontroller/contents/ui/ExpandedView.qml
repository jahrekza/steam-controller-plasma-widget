import QtQuick
import QtQuick.Layouts

// Popup from the panel / system tray icon: the same card as on the desktop — icons and
// colours instead of text, readable in any language. Inside the system tray it lives in
// the tray's own popup, whose width varies, so the card adapts (it may shrink a little).
// Settings: right-click, like any widget.
//
// A plain Item with explicit sizes; the card inside keeps its proportions.
// (The tray only opens this popup because main.qml leaves preferredRepresentation unset.)
Item {
    id: popup

    implicitWidth: 320
    implicitHeight: Math.round(implicitWidth * 208 / 254)
    Layout.minimumWidth: 204
    Layout.minimumHeight: Math.round(204 * 208 / 254)

    // The tray popup has one height for every applet (often much taller than the card),
    // so keep the card's own proportions and centre it instead of stretching it
    DesktopCard {
        embedded: true
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height * 254 / 208)
        height: width * 208 / 254
    }
}
