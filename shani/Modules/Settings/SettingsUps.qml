// Settings > Power: the UPS a desktop runs on (Services/Ups, NUT), when there is one -
// on mains or on its battery, its charge, how long it would last, how loaded it is.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    property bool active: false
    visible: Ups.present
    spacing: 6
    onActiveChanged: if (active) Ups.refresh()
    SectionTitle { objectName: "ups"; Layout.fillWidth: true; text: Tr.t("UPS") }
    Text {
        Layout.fillWidth: true
        text: Ups.info.model || Ups.info.name || ""
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 13 * Theme.fontScale
        font.weight: Font.DemiBold
    }
    Text {
        Layout.fillWidth: true
        text: [Ups.low ? Tr.t("On its battery - low") : Ups.onBattery ? Tr.t("On its battery: the power is out") : Tr.t("On mains power"),
               Ups.says(Ups.info),
               Ups.info.load !== null && Ups.info.load !== undefined ? Tr.t("load %1%", Math.round(Ups.info.load)) : ""].filter(x => x).join("  ·  ")
        color: Ups.low ? Theme.danger : (Ups.onBattery ? Theme.accent : Theme.dim)
        wrapMode: Text.WordWrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    // the charge, as a bar
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: 6
        radius: 3
        color: Theme.hover
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, (Ups.info.charge || 0) / 100))
            height: parent.height
            radius: 3
            color: Ups.low ? Theme.danger : Theme.accent
        }
    }
}
