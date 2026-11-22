// Contacts: the address book — vCard 4.0 files in
// ~/.local/share/shani-link/contacts/, one .vcf per contact. Add, edit,
// delete, search, import .vcf files, merge duplicates. The same files
// Shani Link (the phone app) reads, so a contact added here is there too.
// No CardDAV sync in the shell itself — sync is handled by whatever the
// person already uses (vdirsyncer, Nextcloud, iCloud, Dropbox).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Contacts"
    visible: Ui.contacts
    onGone: Ui.contacts = false
    implicitWidth: Theme.px(680)
    implicitHeight: Theme.px(580)

    // edit mode: "list" (default), "add", or "edit"
    property string mode: "list"
    property string editName: ""
    property string editPhone: ""
    property string editEmail: ""
    property string editUid: ""
    property string editGroups: ""
    property bool showGroupField: false
    property string groupFilter: Tr.t("All")

    // delete asks first: two taps, the second within 4 s
    property string confirmDelete: ""
    Timer { id: deleteTimer; interval: 4000; onTriggered: win.confirmDelete = "" }

    // duplicates view
    property bool showDuplicates: false

    onVisibleChanged: if (visible) Contacts.refresh()

    function pickImport() {
        FilePicker.open({
            mode: "open",
            title: Tr.t("Import vCard"),
            filters: ["vcf"],
            onPicked: paths => {
                if (paths && paths.length > 0) Contacts.importFile(paths[0]);
            }
        });
    }

    // Esc: leave edit mode first, then duplicates, then close
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: {
            if (win.mode !== "list") win.mode = "list";
            else if (win.showDuplicates) win.showDuplicates = false;
            else Ui.contacts = false;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(16)
        spacing: Theme.px(8)

        // ---- header row: title + actions ----
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: win.mode === "add" ? Tr.t("New contact")
                    : win.mode === "edit" ? Tr.t("Edit contact")
                    : win.showDuplicates ? Tr.t("Merge duplicates")
                    : Tr.t("Contacts")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(16) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            Button {
                visible: win.mode === "list" && !win.showDuplicates
                text: Tr.t("Merge duplicates…")
                flat: true
                enabled: Contacts.findDuplicates().length > 0
                onClicked: win.showDuplicates = true
            }
            Button {
                visible: win.mode === "list" && !win.showDuplicates
                text: Tr.t("Import…")
                flat: true
                onClicked: win.pickImport()
            }
            Button {
                visible: win.mode === "list" && !win.showDuplicates
                text: Tr.t("New contact")
                kind: "primary"
                onClicked: { win.mode = "add"; win.editName = ""; win.editPhone = ""; win.editEmail = ""; win.editUid = ""; win.editGroups = ""; win.showGroupField = false; }
            }
            Button {
                visible: win.mode !== "list"
                text: Tr.t("Cancel")
                flat: true
                onClicked: win.mode = "list"
            }
            Button {
                visible: win.mode === "add" || win.mode === "edit"
                text: win.mode === "add" ? Tr.t("Save") : Tr.t("Save changes")
                kind: "primary"
                enabled: win.editName.trim() !== ""
                onClicked: {
                    const groups = win.editGroups.split(",").map(s => s.trim()).filter(s => s);
                    if (win.mode === "add") Contacts.add(win.editName, win.editPhone, win.editEmail, groups);
                    else Contacts.edit(win.editUid, win.editName, win.editPhone, win.editEmail, groups);
                    win.mode = "list";
                }
            }
        }

        // ---- edit form ----
        ColumnLayout {
            visible: win.mode === "add" || win.mode === "edit"
            Layout.fillWidth: true
            spacing: Theme.px(6)

            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Full name")
                label: Tr.t("Full name")
                text: win.editName
                onTextChanged: win.editName = text
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Phone number")
                label: Tr.t("Phone number")
                text: win.editPhone
                onTextChanged: win.editPhone = text
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Email address")
                label: Tr.t("Email address")
                text: win.editEmail
                onTextChanged: win.editEmail = text
            }
            Button {
                text: win.showGroupField ? Tr.t("Hide groups") : Tr.t("Group…")
                flat: true
                onClicked: win.showGroupField = !win.showGroupField
            }
            TextField {
                visible: win.showGroupField
                Layout.fillWidth: true
                placeholder: Tr.t("Groups, comma-separated")
                label: Tr.t("Groups")
                text: win.editGroups
                onTextChanged: win.editGroups = text
            }
            Text {
                visible: Contacts.error !== ""
                text: Contacts.error
                color: Theme.red
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }

        // ---- duplicates view ----
        ColumnLayout {
            visible: win.showDuplicates
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(6)

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("These contacts look like the same person. Click a row to merge them — one card keeps all their phone numbers and emails.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            ListView {
                id: dupList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Contacts.findDuplicates()
                delegate: Rectangle {
                    required property var modelData
                    width: dupList.width
                    height: Theme.px(56)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(12)
                        anchors.rightMargin: Theme.px(12)
                        spacing: Theme.px(10)
                        Icon { name: "contact-new"; size: Theme.px(22); color: Theme.dim }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: (Contacts.contacts.find(c => c.uid === modelData[0]) || {}).name || "—"
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(13) * Theme.fontScale
                            }
                            Text {
                                text: (Contacts.contacts.find(c => c.uid === modelData[1]) || {}).name || "—"
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                        }
                        Button { text: Tr.t("Merge"); kind: "outline"; onClicked: Contacts.merge(modelData[0], modelData[1]) }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: dupList.count === 0
                    icon: "emblem-ok"
                    title: Tr.t("No duplicates found")
                    subtitle: Tr.t("All your contacts look unique")
                }
            }
            Button {
                text: Tr.t("Done")
                flat: true
                onClicked: win.showDuplicates = false
            }
        }

        // ---- search + list ----
        RowLayout {
            visible: win.mode === "list" && !win.showDuplicates
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholder: Tr.t("Search name, phone, or email")
                label: Tr.t("Search contacts")
                onTextChanged: { Contacts.query = text; Contacts.refresh(); }
            }
        }

        Flow {
            visible: win.mode === "list" && !win.showDuplicates
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: Contacts.allGroups
                Choice {
                    required property string modelData
                    text: modelData
                    selected: win.groupFilter === modelData
                    onClicked: win.groupFilter = modelData
                }
            }
        }

        ListView {
            id: list
            visible: win.mode === "list" && !win.showDuplicates
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            reuseItems: true
            cacheBuffer: 400
            model: win.groupFilter === Tr.t("All") ? Contacts.shown : Contacts.listContactsInGroup(win.groupFilter)
            delegate: Rectangle {
                required property var modelData
                width: list.width
                height: Theme.px(52)
                radius: Theme.radiusSmall
                color: rowArea.containsMouse ? Theme.hover : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.px(8)
                    anchors.rightMargin: Theme.px(6)
                    spacing: Theme.px(10)
                    Icon { name: "contact-new"; size: Theme.px(22); color: Theme.dim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: (modelData.name || Tr.t("Unnamed")) + (modelData.uid === Contacts.myUid ? "  ·  " + Tr.t("You") : "")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: text !== ""
                            text: [modelData.phone, modelData.email].filter(x => x).join("  ·  ")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    IconButton {
                        size: Theme.px(28)
                        icon: modelData.uid === Contacts.myUid ? "starred" : "avatar-default"
                        tip: modelData.uid === Contacts.myUid ? Tr.t("This is you") : Tr.t("This is me")
                        onClicked: Contacts.toggleMe(modelData.uid)
                    }
                    IconButton {
                        size: Theme.px(28)
                        icon: "user-trash"
                        tip: win.confirmDelete === modelData.uid
                            ? Tr.t("Click again to delete %1", modelData.name || "")
                            : Tr.t("Delete %1", modelData.name || "")
                        onClicked: {
                            if (win.confirmDelete === modelData.uid) {
                                Contacts.remove(modelData.uid);
                                win.confirmDelete = "";
                            } else {
                                win.confirmDelete = modelData.uid;
                                deleteTimer.restart();
                            }
                        }
                    }
                }
                MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                MouseArea {
                    anchors.fill: parent
                    z: 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        win.mode = "edit";
                        win.editUid = modelData.uid;
                        win.editName = modelData.name || "";
                        win.editPhone = modelData.phone || "";
                        win.editEmail = modelData.email || "";
                        win.editGroups = (modelData.groups || []).join(", ");
                        win.showGroupField = (modelData.groups || []).length > 0;
                    }
                }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: list.count === 0 && !Contacts.busy
                icon: "contact-new"
                title: Contacts.query !== "" ? Tr.t("No matches for %1", Contacts.query) : Tr.t("No contacts yet")
                subtitle: Contacts.query !== "" ? Tr.t("Try a different name or number") : Tr.t("Add one above, or import a .vcf file")
            }
        }

        // ---- footer ----
        Text {
            visible: win.mode === "list" && !win.showDuplicates
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Tr.t("%1 contact%2 · Esc closes", Contacts.contacts.length, Contacts.contacts.length === 1 ? "" : "s")
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
        }
    }
}