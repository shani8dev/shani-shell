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
    // typed phone/email rows in the editor (the bridge already stores arrays)
    property var editPhones: []
    property var editEmails: []
    property string avatarPath: ""
    property string detailUid: ""
    property bool showDetail: false
    property bool showGroupField: false
    property string groupFilter: Tr.t("All")

    // delete asks first: two taps, the second within 4 s
    property string confirmDelete: ""
    Timer { id: deleteTimer; interval: 4000; onTriggered: win.confirmDelete = "" }

    // duplicates view
    property bool showDuplicates: false

    onVisibleChanged: if (visible) Contacts.refresh()
    Connections {
        target: Contacts
        function onVcardReady(text, name) { Qr.show(name || "Contact", text); }
    }
    function setPhone(i, key, value) {
        const rows = win.editPhones.map(x => Object.assign({}, x));
        rows[i][key] = value; win.editPhones = rows;
    }
    function setEmail(i, key, value) {
        const rows = win.editEmails.map(x => Object.assign({}, x));
        rows[i][key] = value; win.editEmails = rows;
    }
    function showContact(c) {
        if (!c) return;
        win.detailUid = c.uid;
        win.showDetail = true;
    }
    function openExternal(url) { Quickshell.execDetached(["xdg-open", url]); }

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
            if (win.showDetail) win.showDetail = false;
            else if (win.mode !== "list") win.mode = "list";
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
                text: "Export all…"
                flat: true
                enabled: Contacts.contacts.length > 0
                onClicked: FilePicker.open({ mode: "save", title: "Export contacts", defaultName: "contacts.vcf",
                    filters: ["vcf"], onPicked: paths => { if (paths.length) Contacts.exportAll(paths[0]); } })
            }
            Button {
                visible: win.mode === "list" && !win.showDuplicates
                text: Tr.t("New contact")
                kind: "primary"
                onClicked: { win.mode = "add"; win.editName = ""; win.editPhone = ""; win.editEmail = ""; win.editUid = ""; win.editGroups = ""; win.editPhones = []; win.editEmails = []; win.avatarPath = ""; win.showGroupField = false; }
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
                    const c = Contacts.contacts.find(x => x.uid === win.editUid) || {};
                    const detail = { phones: win.editPhones, emails: win.editEmails,
                        given: c.given || "", family: c.family || "",
                        favorite: !!c.favorite, avatar: win.avatarPath || c.avatar || "" };
                    if (win.mode === "add") Contacts.add(win.editName, win.editPhone, win.editEmail, groups, detail);
                    else Contacts.edit(win.editUid, win.editName, win.editPhone, win.editEmail, groups, detail);
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
            Text { text: "Phone numbers"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Repeater {
                model: win.editPhones
                RowLayout {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    TextField {
                        Layout.preferredWidth: Theme.px(96)
                        text: modelData.type || "cell"
                        placeholder: "cell / home / work"
                        onTextChanged: win.setPhone(index, "type", text)
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: modelData.number || ""
                        placeholder: Tr.t("Phone number")
                        onTextChanged: win.setPhone(index, "number", text)
                    }
                    IconButton { size: Theme.px(24); icon: "list-remove"; tip: "Remove"; onClicked: { const rows = win.editPhones.slice(); rows.splice(index, 1); win.editPhones = rows; } }
                }
            }
            Button { text: "Add phone"; flat: true; onClicked: win.editPhones = win.editPhones.concat([{ type: "cell", number: "" }]) }
            Text { text: "Email addresses"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Repeater {
                model: win.editEmails
                RowLayout {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    TextField {
                        Layout.preferredWidth: Theme.px(96)
                        text: modelData.type || "home"
                        placeholder: "home / work"
                        onTextChanged: win.setEmail(index, "type", text)
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: modelData.address || ""
                        placeholder: Tr.t("Email address")
                        onTextChanged: win.setEmail(index, "address", text)
                    }
                    IconButton { size: Theme.px(24); icon: "list-remove"; tip: "Remove"; onClicked: { const rows = win.editEmails.slice(); rows.splice(index, 1); win.editEmails = rows; } }
                }
            }
            Button { text: "Add email"; flat: true; onClicked: win.editEmails = win.editEmails.concat([{ type: "home", address: "" }]) }
            Button {
                text: "Set photo…"
                flat: true
                onClicked: FilePicker.open({ mode: "open", title: "Contact photo", filters: ["png", "jpg", "jpeg", "webp"],
                    onPicked: paths => { if (paths.length) win.avatarPath = paths[0]; } })
            }
            Text {
                visible: win.avatarPath !== ""
                text: "Photo: " + win.avatarPath
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                elide: Text.ElideMiddle
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
                model: [["name", "Name"], ["given", "Given"], ["family", "Family"]]
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: Contacts.sortBy === modelData[0]
                    onClicked: { Contacts.sortBy = modelData[0]; Settings.data.contactsSortBy = modelData[0]; Settings.save(); }
                }
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
                    Rectangle {
                        width: Theme.px(30); height: Theme.px(30)
                        radius: width / 2
                        color: Theme.accentSoft
                        border.width: 1
                        border.color: Theme.border
                        clip: true
                        Image {
                            anchors.fill: parent
                            visible: !!modelData.avatar
                            source: modelData.avatar ? ("file://" + modelData.avatar) : ""
                            fillMode: Image.PreserveAspectCrop
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !modelData.avatar
                            text: ((modelData.name || "?").charAt(0) || "?").toUpperCase()
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: (modelData.name || Tr.t("Unnamed")) + (modelData.uid === Contacts.myUid ? "  ·  " + Tr.t("You") : "") + (modelData.favorite ? "  ★" : "")
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
                        icon: modelData.favorite ? "starred" : "non-starred"
                        tip: modelData.favorite ? "Remove from favourites" : "Add to favourites"
                        onClicked: Contacts.toggleFavorite(modelData.uid)
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
                    onClicked: win.showContact(modelData)
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

    // ---- read-only detail sheet: call, mail, map, QR, then edit --------------
    Rectangle {
        visible: win.showDetail
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: win.showDetail = false }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.px(32), Theme.px(440))
            implicitHeight: detailCol.implicitHeight + Theme.px(24)
            radius: Theme.radiusLarge
            color: Theme.surface1
            border.width: 1
            border.color: Theme.border
            ColumnLayout {
                id: detailCol
                anchors { fill: parent; margins: Theme.px(12) }
                spacing: Theme.px(6)
                property var c: Contacts.contacts.find(x => x.uid === win.detailUid) || {}
                RowLayout {
                    Layout.fillWidth: true
                    Rectangle {
                        width: Theme.px(44); height: Theme.px(44)
                        radius: width / 2
                        color: Theme.accentSoft
                        clip: true
                        Image {
                            anchors.fill: parent
                            visible: !!detailCol.c.avatar
                            source: detailCol.c.avatar ? ("file://" + detailCol.c.avatar) : ""
                            fillMode: Image.PreserveAspectCrop
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !detailCol.c.avatar
                            text: ((detailCol.c.name || "?").charAt(0) || "?").toUpperCase()
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.px(19) * Theme.fontScale
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: detailCol.c.name || ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(15) * Theme.fontScale
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                }
                Repeater {
                    model: detailCol.c.phones || []
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Icon { name: "call-start"; size: Theme.px(18); color: Theme.dim }
                        Text { Layout.fillWidth: true; text: (modelData.type || "cell") + ": " + (modelData.number || ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; elide: Text.ElideRight }
                        Button { text: "Call"; flat: true; onClicked: win.openExternal("tel:" + (modelData.number || "")) }
                    }
                }
                Repeater {
                    model: detailCol.c.emails || []
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Icon { name: "mail-unread"; size: Theme.px(18); color: Theme.dim }
                        Text { Layout.fillWidth: true; text: (modelData.type || "home") + ": " + (modelData.address || ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; elide: Text.ElideRight }
                        Button { text: "Mail"; flat: true; onClicked: win.openExternal("mailto:" + (modelData.address || "")) }
                    }
                }
                Button {
                    text: "Open in Maps"
                    flat: true
                    enabled: !!((detailCol.c.name || ""))
                    onClicked: win.openExternal("https://www.openstreetmap.org/search?query=" + encodeURIComponent(detailCol.c.name || ""))
                }
                Text {
                    visible: !!((detailCol.c.favorite))
                    text: "★ Favourite"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Button { text: "QR code"; flat: true; onClicked: Contacts.vcard(win.detailUid, detailCol.c.name || "Contact") }
                    Button { Layout.fillWidth: true; text: Tr.t("Close"); onClicked: win.showDetail = false }
                    Button {
                        Layout.fillWidth: true; text: Tr.t("Edit"); kind: "primary"
                        enabled: !!(detailCol.c.uid)
                        onClicked: {
                            const c = detailCol.c;
                            win.showDetail = false;
                            win.mode = "edit";
                            win.editUid = c.uid || "";
                            win.editName = c.name || "";
                            win.editPhone = c.phone || "";
                            win.editEmail = c.email || "";
                            win.editGroups = (c.groups || []).join(", ");
                            win.editPhones = (c.phones || []).map(x => Object.assign({}, x));
                            win.editEmails = (c.emails || []).map(x => Object.assign({}, x));
                            win.avatarPath = c.avatar || "";
                            win.showGroupField = (c.groups || []).length > 0;
                        }
                    }
                }
            }
        }
    }
}