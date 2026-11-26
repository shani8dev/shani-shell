// Files to and from the phone. One implementation for every window that shows
// them (Calls and Devices): a file is chosen with the shell's picker, never
// typed; the switch keeps receiving on even when the window is closed.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: root
    spacing: Theme.px(10)

    BusyNote {
        visible: PhoneTools.busy
        Layout.fillWidth: true
        note: Tr.t("Working…")
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(8)
        Button {
            Layout.fillWidth: true
            text: Tr.t("Choose a file to send")
            kind: "primary"
            enabled: !PhoneTools.busy
            onClicked: {
                if (!Ui.filePicker) return;
                Ui.filePicker.open({
                    "mode": "open",
                    "title": Tr.t("Choose a file to send"),
                    "onPicked": paths => { if (paths && paths.length) PhoneTools.filesSend(paths[0]); }
                });
            }
        }
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Receive files from the phone")
        checked: PhoneTools.receiveFiles
        onToggled: on => PhoneTools.filesReceive(on)
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Received files")
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.type("body")
        font.weight: Font.DemiBold
    }
    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(Theme.px(120), Theme.px(56) * Math.min(3, count))
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: PhoneTools.files
        delegate: ListRow {
            required property var modelData
            width: ListView.view.width
            icon: "document"
            title: modelData.name || modelData.path || Tr.t("File")
            subtitle: [typeof modelData.size === "number" ? Theme.bytes(modelData.size) : "",
                       Link.when(modelData.when)].filter(x => String(x) !== "").join("  ·  ")
            trailing: ""
            interactive: false
            IconButton {
                icon: "document-open"
                size: Theme.px(24)
                tip: Tr.t("Open")
                accessibleName: Tr.t("Open %1", modelData.name || Tr.t("File"))
                onClicked: Files.openEntry(modelData.path)
            }
            IconButton {
                icon: "folder-open"
                size: Theme.px(24)
                tip: Tr.t("Show in Files")
                accessibleName: Tr.t("Show %1 in Files", modelData.name || Tr.t("File"))
                onClicked: {
                    const p = modelData.path || "";
                    const at = p.lastIndexOf("/");
                    Files.show(at === 0 ? "/" : p.substring(0, at));
                    Files.select(p, "single");
                }
            }
        }
    }
    EmptyState {
        visible: PhoneTools.files.length === 0
        icon: "folder"
        title: Tr.t("No files yet")
        subtitle: Tr.t("Files sent by the phone show up here")
    }
    Text {
        Layout.fillWidth: true
        visible: PhoneTools.note !== ""
        text: PhoneTools.note
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.type("small")
        wrapMode: Text.Wrap
    }
    Item { Layout.fillHeight: true }
}
