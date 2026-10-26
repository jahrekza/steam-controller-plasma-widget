import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// Tooltip: title, status line and a graph of the battery over the last hours
// (from the daemon's history, up to 24 h). Charging stretches in the cable colour,
// gaps where the controller was off.
ColumnLayout {
    id: tip
    spacing: Kirigami.Units.smallSpacing
    width: Kirigami.Units.gridUnit * 17

    // history points [unix time, %, charging 0/1]
    readonly property var points: root.history
    readonly property real span: points.length > 1 ? points[points.length - 1][0] - points[0][0] : 0
    onPointsChanged: graph.requestPaint()

    PC3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: root.toolTipMainText
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
    PC3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing
        text: root.toolTipSubText
        opacity: 0.75
        wrapMode: Text.Wrap
    }

    Canvas {
        id: graph
        visible: tip.span >= 600
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3.5
        Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset()
            var p = tip.points, n = p.length
            if (n < 2 || tip.span <= 0) return
            var w = width, h = height, t0 = p[0][0]
            function X(t) { return (t - t0) / tip.span * w }
            function Y(v) { return h - v / 100 * (h - 4) - 2 }
            var text = Kirigami.Theme.textColor, chg = root.colorCable
            c.strokeStyle = Qt.rgba(text.r, text.g, text.b, 0.12); c.lineWidth = 1
            for (var g of [0, 50, 100]) { c.beginPath(); c.moveTo(0, Y(g)); c.lineTo(w, Y(g)); c.stroke() }
            for (var i = 1; i < n; i++) {
                var a = p[i - 1], b = p[i]
                if (b[0] - a[0] > 900) continue            // controller was off: leave a gap
                var col = b[2] ? chg : text
                c.fillStyle = Qt.rgba(col.r, col.g, col.b, b[2] ? 0.45 : 0.22)
                c.beginPath(); c.moveTo(X(a[0]), h); c.lineTo(X(a[0]), Y(a[1]))
                c.lineTo(X(b[0]), Y(b[1])); c.lineTo(X(b[0]), h); c.closePath(); c.fill()
                c.strokeStyle = col; c.lineWidth = 2
                c.beginPath(); c.moveTo(X(a[0]), Y(a[1])); c.lineTo(X(b[0]), Y(b[1])); c.stroke()
            }
        }
    }
    RowLayout {
        visible: graph.visible
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        PC3.Label {
            text: tip.span >= 3600 ? root.tr("−%1 h", Math.round(tip.span / 3600)) : root.tr("−%1 min", Math.round(tip.span / 60))
            font: Kirigami.Theme.smallFont; opacity: 0.6
        }
        Item { Layout.fillWidth: true }
        PC3.Label { text: root.tr("now"); font: Kirigami.Theme.smallFont; opacity: 0.6 }
    }
}
