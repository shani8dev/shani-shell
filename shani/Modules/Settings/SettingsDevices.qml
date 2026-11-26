// Settings > Devices: a door to the Devices app, which owns every device flow
// (pairing, this screen on a phone, and the radio gadgets). Nothing here talks
// to a device; the only setting on this page is where the app opens.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: page
    property bool active: false
    spacing: Theme.px(12)

    function open(tab) {
        Ui.devicesTab = tab;
        Ui.closeAll();
        Ui.devices = true;
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Tr.t("Devices")
        hint: Tr.t("Phones, pairing, showing this screen on a phone, and the small radio gadgets are all in one app.")
        ListRow {
            Layout.fillWidth: true
            icon: "smartphone"
            title: Tr.t("Phones and pairing")
            subtitle: Tr.t("Paired devices, connect a device, phone link and lines")
            onClicked: page.open("phones")
        }
        ListRow {
            Layout.fillWidth: true
            icon: "video-display"
            title: Tr.t("This screen on a phone")
            subtitle: Tr.t("Show one window or the whole screen, with touch and typing")
            onClicked: page.open("screen")
        }
        ListRow {
            Layout.fillWidth: true
            icon: "radio"
            title: Tr.t("Radio gadgets")
            subtitle: Tr.t("Nearby tags, infrared codes and local radio")
            onClicked: page.open("gadgets")
        }
    }
}
