import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kquickcontrols as KQControls

// Settings row: "Custom" checkbox + colour button. value "" = default (fallback).
RowLayout {
    id: choice
    property string value
    property color fallback
    signal picked(string value)

    QQC2.CheckBox {
        id: custom
        text: page.tr("Custom")
        checked: choice.value !== ""
        onToggled: choice.picked(checked ? button.color.toString() : "")
    }
    KQControls.ColorButton {
        id: button
        enabled: custom.checked
        color: choice.value !== "" ? choice.value : choice.fallback
        onAccepted: function(chosen) { choice.picked(chosen.toString()) }
    }
}
