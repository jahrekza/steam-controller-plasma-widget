import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kquickcontrols as KQControls
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_lowThreshold: threshold.value
    property alias cfg_notifyLow: notifyLow.checked
    property string cfg_illustrationColor     // "" = follow the theme
    property alias cfg_showSignalCard: showSignalCard.checked
    property alias cfg_showSignalTray: showSignalTray.checked
    // defaults handed in by the config dialog (declared so it doesn't warn)
    property int cfg_lowThresholdDefault
    property bool cfg_notifyLowDefault
    property string cfg_illustrationColorDefault
    property bool cfg_showSignalCardDefault
    property bool cfg_showSignalTrayDefault
    property alias cfg_signalStyle: signalStyle.currentIndex
    property int cfg_signalStyleDefault

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: threshold
            Kirigami.FormData.label: i18n("Low battery warning:")
            from: 5; to: 50; stepSize: 5
            textFromValue: function(value) { return value + "%" }
            valueFromText: function(text) { return parseInt(text) }
        }
        QQC2.CheckBox {
            id: notifyLow
            text: i18n("Send a notification when the battery drops below it")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Controller colour:")
            QQC2.CheckBox {
                id: customColor
                text: i18n("Custom")
                checked: cfg_illustrationColor !== ""
                onToggled: cfg_illustrationColor = checked ? colorButton.color.toString() : ""
            }
            KQControls.ColorButton {
                id: colorButton
                enabled: customColor.checked
                color: cfg_illustrationColor !== "" ? cfg_illustrationColor : Kirigami.Theme.textColor
                onAccepted: function(chosen) { cfg_illustrationColor = chosen.toString() }
            }
        }
        QQC2.Label {
            text: i18n("Unticked: the controller follows the Plasma theme's text colour.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        QQC2.CheckBox {
            id: showSignalCard
            Kirigami.FormData.label: i18n("Signal strength:")
            text: i18n("Show on the widget (desktop card)")
        }
        QQC2.CheckBox {
            id: showSignalTray
            text: i18n("Show in the panel / system tray, next to the percentage")
        }
        QQC2.ComboBox {
            id: signalStyle
            Kirigami.FormData.label: i18n("Show as:")
            model: [i18n("Bars"), i18n("Bars and dBm"), i18n("dBm only")]
        }
        QQC2.Label {
            text: i18n("Only for the wireless puck (also the Steam Machine's). Over Bluetooth or a cable there is no signal reading.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }
    }
}
