// The phone's camera and media keys, as big buttons. Nothing is typed to use
// the six keys; a custom command is only for a key this shell does not list.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: root
    spacing: Theme.px(10)

    function sendCustom() {
        const c = custom.text.trim();
        if (c === "") return;
        PhoneTools.remoteAction("press", c);
        custom.text = "";
    }

    BusyNote {
        visible: PhoneTools.busy
        Layout.fillWidth: true
        note: Tr.t("Working…")
    }
    EmptyState {
        visible: PhoneTools.remote.on !== true
        icon: "phone"
        title: Tr.t("Remote control is off")
        subtitle: Tr.t("Turn it on to use the phone's camera and media keys")
        actionText: Tr.t("Turn on")
        onAction: PhoneTools.remoteAction("on")
    }
    ColumnLayout {
        visible: PhoneTools.remote.on === true
        Layout.fillWidth: true
        spacing: Theme.px(8)
        GridLayout {
            Layout.fillWidth: true
            columns: root.width < Theme.px(420) ? 2 : 3
            rowSpacing: Theme.px(8)
            columnSpacing: Theme.px(8)
            Repeater {
                model: [
                    { label: Tr.t("Take a photo"), name: Tr.t("Take a photo"), key: "shutter" },
                    { label: Tr.t("Previous"), name: Tr.t("Previous on the phone"), key: "previous" },
                    { label: Tr.t("Play or pause"), name: Tr.t("Play or pause on the phone"), key: "play_pause" },
                    { label: Tr.t("Next"), name: Tr.t("Next on the phone"), key: "next" },
                    { label: Tr.t("Volume down"), name: Tr.t("Volume down on the phone"), key: "volume_down" },
                    { label: Tr.t("Volume up"), name: Tr.t("Volume up on the phone"), key: "volume_up" }
                ]
                Button {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(52)
                    text: modelData.label
                    Accessible.name: modelData.name
                    kind: "outline"
                    onClicked: PhoneTools.remoteAction("press", modelData.key)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(8)
            TextField {
                id: custom
                Layout.fillWidth: true
                label: Tr.t("Another command")
                placeholder: Tr.t("Another command, if needed")
                onAccepted: root.sendCustom()
            }
            Button {
                text: Tr.t("Send")
                kind: "primary"
                enabled: custom.text.trim() !== ""
                onClicked: root.sendCustom()
            }
        }
        Text {
            Layout.fillWidth: true
            visible: PhoneTools.remote.status || PhoneTools.note
            text: PhoneTools.note !== "" ? PhoneTools.note : String(PhoneTools.remote.status || "")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            wrapMode: Text.Wrap
        }
    }
    Item { Layout.fillHeight: true }
}
