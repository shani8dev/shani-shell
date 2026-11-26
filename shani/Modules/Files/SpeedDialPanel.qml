// Speed Dial in the Files sidebar: named shortcuts to folders and files, kept
// in sections. The model and the rules live in Services/SpeedDial.qml (JSON in
// the shell's state folder); this is only the surface. Unlike the GTK bookmarks
// in Places, these are the shell's own and can be named, grouped and re-pinned.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/FilePaths.js" as FilePaths

ColumnLayout {
    id: panel
    objectName: "region:speedDial"
    Layout.fillWidth: true
    spacing: Theme.px(3)

    // "" | "section" | "rename-section|<section>" | "entry|<section>" | "rename-entry|<section>|<name>"
    property string form: ""
    property string draftName: ""
    property string draftPath: ""
    property string confirm: ""
    readonly property string formKind: panel.form.split("|")[0]
    readonly property string formSection: panel.form.split("|")[1] || ""
    readonly property string formOld: panel.form.split("|")[2] || ""

    function openForm(kind, section, oldName) {
        panel.confirm = "";
        panel.form = kind + (section ? "|" + section : "") + (oldName ? "|" + oldName : "");
        panel.draftName = oldName || "";
        panel.draftPath = kind === "entry" && Files.path.startsWith("/") ? Files.path : "";
        SpeedDial.clearError();
    }
    function closeForm() {
        panel.form = "";
        panel.draftName = "";
        panel.draftPath = "";
    }
    function submit() {
        const n = panel.draftName.trim();
        let ok = false;
        if (panel.formKind === "section") ok = SpeedDial.addSection(n);
        else if (panel.formKind === "rename-section") ok = SpeedDial.renameSection(panel.formSection, n);
        else if (panel.formKind === "entry") ok = SpeedDial.addEntry(panel.formSection, n, panel.draftPath.trim());
        else if (panel.formKind === "rename-entry") ok = SpeedDial.renameEntry(panel.formSection, panel.formOld, n);
        if (ok) panel.closeForm();
    }
    function isAsking(key) { return panel.confirm === key; }
    function asking(key) {
        if (panel.confirm !== key) {
            panel.confirm = key;
            confirmTimer.restart();
            return false;
        }
        panel.confirm = "";
        return true;
    }
    function iconFor(path) {
        if (/\.(png|jpe?g|webp|gif|avif|heic|svg)$/i.test(path)) return "image-x-generic";
        if (/\.(mp3|flac|ogg|opus|wav|m4a)$/i.test(path)) return "audio-x-generic";
        if (/\.(mp4|mkv|webm|mov|avi)$/i.test(path)) return "video-x-generic";
        if (/\.(zip|tar|gz|xz|zst|bz2|7z|rar)$/i.test(path)) return "package-x-generic";
        if (/\.(txt|md|log|json|ya?ml|toml|ini|csv|xml|html|css|js|ts|py|sh|pdf)$/i.test(path)) return "text-x-generic";
        return "folder";
    }
    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: panel.confirm = ""
    }

    SectionTitle {
        Layout.fillWidth: true
        text: Tr.t("Speed Dial")
        IconButton {
            icon: "list-add"
            size: Theme.px(20)
            tip: Tr.t("Add a section")
            onClicked: panel.openForm("section", "", "")
        }
    }

    // One inline form for every add/rename flow: no modal to lose your place in
    // the file manager. Enter on either field submits; Escape closes it.
    ColumnLayout {
        visible: panel.form !== ""
        Layout.fillWidth: true
        spacing: Theme.px(4)
        TextField {
            id: nameField
            Layout.fillWidth: true
            label: panel.formKind.indexOf("rename") === 0 ? Tr.t("New name") : Tr.t("Name")
            placeholder: Tr.t("Name")
            text: panel.draftName
            onTextChanged: panel.draftName = text
            onAccepted: panel.submit()
            Keys.onEscapePressed: { panel.closeForm(); SpeedDial.clearError(); }
        }
        TextField {
            visible: panel.formKind === "entry"
            Layout.fillWidth: true
            label: Tr.t("Folder or file path")
            placeholder: Tr.t("/home/me/Documents")
            text: panel.draftPath
            onTextChanged: panel.draftPath = text
            onAccepted: panel.submit()
            Keys.onEscapePressed: { panel.closeForm(); SpeedDial.clearError(); }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(4)
            Button {
                Layout.fillWidth: true
                text: panel.formKind.indexOf("rename") === 0 ? Tr.t("Rename") : Tr.t("Add")
                kind: "primary"
                onClicked: panel.submit()
            }
            Button {
                text: Tr.t("Cancel")
                onClicked: panel.closeForm()
            }
        }
    }

    Text {
        visible: SpeedDial.error !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: SpeedDial.error
        color: Theme.danger
        font.family: Theme.font
        font.pixelSize: Theme.type("caption")
        Accessible.role: Accessible.AlertMessage
        Accessible.name: SpeedDial.error
    }

    Repeater {
        model: SpeedDial.sections()
        ColumnLayout {
            id: sectionColumn
            required property var modelData
            property string sectionName: modelData.name
            Layout.fillWidth: true
            spacing: Theme.px(2)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(2)
                Text {
                    Layout.fillWidth: true
                    text: sectionColumn.sectionName + " · " + modelData.count
                    color: Theme.dim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.type("caption")
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                }
                IconButton {
                    icon: "list-add"
                    size: Theme.px(18)
                    tip: Tr.t("Add a shortcut to %1", sectionColumn.sectionName)
                    onClicked: panel.openForm("entry", sectionColumn.sectionName, "")
                }
                IconButton {
                    icon: "edit-rename"
                    size: Theme.px(18)
                    tip: Tr.t("Rename section %1", sectionColumn.sectionName)
                    onClicked: panel.openForm("rename-section", sectionColumn.sectionName, "")
                }
                IconButton {
                    icon: panel.isAsking("section|" + sectionColumn.sectionName) ? "edit-delete" : "window-close"
                    size: Theme.px(18)
                    tip: panel.confirm === "section|" + sectionColumn.sectionName
                         ? Tr.t("Click again to delete section %1", sectionColumn.sectionName)
                         : Tr.t("Delete section %1", sectionColumn.sectionName)
                    onClicked: {
                        if (panel.asking("section|" + sectionColumn.sectionName))
                            SpeedDial.removeSection(sectionColumn.sectionName);
                    }
                }
            }

            // The sidebar stays short: the oldest pins are reached from the
            // application's own Speed Dial mapping, newest first like corebox.
            Repeater {
                model: SpeedDial.entries(sectionColumn.sectionName).slice(0, 8)
                ListRow {
                    id: entryRow
                    required property var modelData
                    Layout.fillWidth: true
                    icon: panel.iconFor(modelData.path)
                    title: modelData.name
                    subtitle: FilePaths.shorten(modelData.path, SpeedDial.home)
                    onClicked: SpeedDial.open(modelData.path)
                    IconButton {
                        icon: panel.isAsking("entry|" + sectionColumn.sectionName + "|" + entryRow.modelData.name) ? "edit-delete" : "list-remove"
                        size: Theme.px(20)
                        tip: panel.confirm === "entry|" + sectionColumn.sectionName + "|" + entryRow.modelData.name
                             ? Tr.t("Click again to remove %1", entryRow.modelData.name)
                             : Tr.t("Remove %1", entryRow.modelData.name)
                        onClicked: {
                            if (panel.asking("entry|" + sectionColumn.sectionName + "|" + entryRow.modelData.name))
                                SpeedDial.removeEntry(sectionColumn.sectionName, entryRow.modelData.name);
                        }
                    }
                    IconButton {
                        icon: "edit-rename"
                        size: Theme.px(20)
                        tip: Tr.t("Rename %1", entryRow.modelData.name)
                        onClicked: panel.openForm("rename-entry", sectionColumn.sectionName, entryRow.modelData.name)
                    }
                }
            }
            Text {
                visible: SpeedDial.entries(sectionColumn.sectionName).length > 8
                Layout.fillWidth: true
                text: Tr.t("… and %1 more", SpeedDial.entries(sectionColumn.sectionName).length - 8)
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.type("caption")
            }
        }
    }

    Text {
        visible: SpeedDial.count() === 0 && panel.form === ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Tr.t("No shortcuts yet. Add a folder you use often, then give it a name.")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: Theme.type("caption")
    }
}
