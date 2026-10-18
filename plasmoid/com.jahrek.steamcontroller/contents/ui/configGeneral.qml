import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_lowThreshold: threshold.value
    property alias cfg_notifyLow: notifyLow.checked

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
    }
}
