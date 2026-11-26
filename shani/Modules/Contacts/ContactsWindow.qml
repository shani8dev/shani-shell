// Contacts: the address book — vCard 4.0 files in
// ~/.local/share/shani-shell/contacts/, one .vcf per contact. Add, edit,
// delete, search, import .vcf files, merge duplicates. The same files
// Phone (the phone app) reads, so a contact added here is there too.
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
    // the rest of the card, from the reference editor; typing stays optional
    property string editBirthday: ""
    property var editAddresses: []
    property string editOrg: ""
    property string editRole: ""
    property string editUrls: ""
    property string editNote: ""
    // typed phone/email rows in the editor (the bridge already stores arrays)
    property var editPhones: []
    property var editEmails: []
    property string avatarPath: ""
    property string detailUid: ""
    property bool showDetail: false
    property bool showGroupField: false
    property string groupFilter: Tr.t("All")
    property int currentIndex: -1          // keyboard selection, keyed by uid not row index
    property string source: "local"        // "local" or "phone" (read-only)
    property bool selecting: false         // click several cards, then export or delete
    property var chosen: []                // uids, never row indexes

    // delete asks first: two taps, the second within 4 s
    property string confirmDelete: ""
    Timer { id: deleteTimer; interval: 4000; onTriggered: win.confirmDelete = "" }

    // duplicates view
    property bool showDuplicates: false

    onVisibleChanged: if (visible) { Contacts.refresh(); win.confirmDelete = ""; }
    // a new filter is a new list: an old row index must not survive it
    onGroupFilterChanged: win.currentIndex = -1
    Connections {
        target: Contacts
        function onVcardReady(text, name) { Qr.show(name || "Contact", text); }
        function onQueryChanged() { win.currentIndex = -1; }
        // launcher and wiki links hand a card over through Contacts.selected
        function onSelectedChanged() { if (Contacts.selected) win.showContact(Contacts.selected); }
    }
    // The form offers four labels; older cards use vCard's "cell" for mobile.
    // Display labels go through Tr.t; the first element is the vCard type key.
    readonly property var phoneTypes: [["home", Tr.t("Home")], ["work", Tr.t("Work")], ["mobile", Tr.t("Mobile")], ["other", Tr.t("Other")]]
    function phoneType(t) {
        const v = String(t || "").toLowerCase();
        return v === "cell" ? "mobile" : win.phoneTypes.some(x => x[0] === v) ? v : "mobile";
    }
    function emailType(t) {
        const v = String(t || "").toLowerCase();
        return win.phoneTypes.some(x => x[0] === v) ? v : "home";
    }
    function setPhone(i, key, value) {
        const rows = win.editPhones.map(x => Object.assign({}, x));
        rows[i][key] = value; win.editPhones = rows;
    }
    function setEmail(i, key, value) {
        const rows = win.editEmails.map(x => Object.assign({}, x));
        rows[i][key] = value; win.editEmails = rows;
    }
    function setAddress(i, key, value) {
        const rows = win.editAddresses.map(x => Object.assign({}, x));
        rows[i][key] = value; win.editAddresses = rows;
    }
    function toggleSelected(uid) {
        const at = win.chosen.indexOf(uid);
        win.chosen = at < 0 ? win.chosen.concat([uid]) : win.chosen.filter(x => x !== uid);
    }
    function toggleSelecting() {
        win.selecting = !win.selecting;
        win.chosen = [];
        win.currentIndex = -1;
    }
    function activateRow(c) {
        if (!c) return;
        if (win.selecting && win.source === "local") win.toggleSelected(c.uid);
        else win.showContact(c);
    }
    function savePhoneContact(c) {
        if (!c) return;
        Contacts.savePhone(c);
        win.showDetail = false;
        win.source = "local";
    }
    function showContact(c) {
        if (!c) return;
        // while choosing several, a row picks itself instead of opening a sheet
        if (win.selecting && win.source === "local") { win.toggleSelected(c.uid); return; }
        const rows = win.visibleContacts();
        const at = rows.findIndex(x => x.uid === c.uid);
        if (at >= 0) win.currentIndex = at;
        win.detailUid = c.uid;
        win.showDetail = true;
    }
    function visibleContacts() {
        if (win.source === "phone") return Contacts.phoneContacts;
        if (win.groupFilter === Tr.t("Favourites")) return Contacts.favoriteContacts;
        if (Contacts.isSmartList(win.groupFilter)) return Contacts.contactsInList(win.groupFilter);
        return win.groupFilter === Tr.t("All") ? Contacts.shown
            : Contacts.listContactsInGroup(win.groupFilter);
    }
    // arrows walk the visible list in both directions and wrap; Enter opens it
    function step(delta) {
        const rows = win.visibleContacts();
        if (!rows.length) return;
        const i = win.currentIndex;
        win.currentIndex = i < 0 ? (delta > 0 ? 0 : rows.length - 1) : (i + delta + rows.length) % rows.length;
        list.positionViewAtIndex(win.currentIndex, ListView.Contain);
    }
    function newContact() {
        win.mode = "add"; win.editName = ""; win.editPhone = ""; win.editEmail = "";
        win.editUid = ""; win.editGroups = ""; win.editPhones = []; win.editEmails = [];
        win.editBirthday = ""; win.editAddresses = []; win.editOrg = ""; win.editRole = "";
        win.editUrls = ""; win.editNote = "";
        win.avatarPath = ""; win.showGroupField = false; win.currentIndex = -1;
    }
    // Apple Contacts / GNOME Contacts both hand a number straight to Messages
    function messageContact(c) {
        if (!c) return;
        const numbers = (c.phones || []).map(p => String(p.number || "").trim())
            .concat((c.numbers || []).map(n => String(n || "").trim())).filter(n => n !== "");
        if (!numbers.length) { Contacts.say(Tr.t("This contact has no phone number")); return; }
        Ui.messagesNumber = numbers[0];
        Ui.messages = true;
    }
    function copyText(value) {
        const s = String(value || "").trim();
        if (s) Quickshell.clipboardText = s;
    }
    function openExternal(url) { Quickshell.execDetached(["xdg-open", url]); }

    // ---- contact -> note ----------------------------------------------------
    property string pendingNoteName: ""
    property string pendingNoteBody: ""
    function contactNoteName(c) {
        const n = QuickNotes.valid((c || {}).name || "");
        return n === "" ? Tr.t("Contact") : Tr.t("Contact: %1").arg(n);
    }
    function contactNoteBody(c) {
        const p = c || {};
        const name = String(p.name || "").trim() || Tr.t("Contact");
        const email = p.email || ((p.emails || [])[0] || {}).address || "";
        const phone = p.phone || ((p.phones || [])[0] || {}).number || "";
        let body = "# " + name + "\n\n";
        if (email) body += "- Email: " + email + "\n";
        if (phone) body += "- Phone: " + phone + "\n";
        return body + "\n[[" + name + "]]\n";   // the link points back to the card
    }
    function contactToNote(c) {
        if (!c) return;
        const name = win.contactNoteName(c);
        Ui.openNotes();
        if (QuickNotes.notes.some(n => n.name === name && n.notebook === "")) {
            QuickNotes.open(name, "");
            return;
        }
        win.pendingNoteName = name;
        win.pendingNoteBody = win.contactNoteBody(c);
        QuickNotes.create(name, "");
        noteFill.restart();
    }
    // shortcut: FileView loads the new file asynchronously; 800 ms is enough
    // on local disk, but a load signal from QuickNotes would be more reliable
    Timer {
        id: noteFill
        interval: 800
        onTriggered: {
            if (QuickNotes.current !== win.pendingNoteName || win.pendingNoteBody === "") return;
            QuickNotes.set(win.pendingNoteBody);
            win.pendingNoteBody = "";
        }
    }

    function pickImport() {
        FilePicker.open({
            mode: "open",
            title: Tr.t("Import vCard"),
            filters: ["vcf"],
            multiple: true,
            onPicked: paths => {
                if (paths) paths.forEach(p => Contacts.importFile(p));
            }
        });
    }

    // Esc: leave detail / edit mode first, then duplicates, then close.
    // Ctrl+F and Ctrl+N are the standard find/new shortcuts; arrows and Enter
    // walk the visible list without ever reaching an unseen row.
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: {
            if (win.showDetail) win.showDetail = false;
            else if (win.mode !== "list") win.mode = "list";
            else if (win.showDuplicates) win.showDuplicates = false;
            else if (win.selecting) win.toggleSelecting();
            else Ui.contacts = false;
        }
        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F) {
                searchField.input.forceActiveFocus(); e.accepted = true;
            } else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N) {
                win.newContact(); e.accepted = true;
            } else if (win.mode === "list" && !win.showDuplicates && (e.key === Qt.Key_Down || e.key === Qt.Key_Up)) {
                win.step(e.key === Qt.Key_Down ? 1 : -1); e.accepted = true;
            } else if (win.mode === "list" && !win.showDuplicates && e.key === Qt.Key_Return && win.currentIndex >= 0) {
                const rows = win.visibleContacts();
                if (rows[win.currentIndex]) {
                    if (win.selecting && win.source === "local") win.toggleSelected(rows[win.currentIndex].uid);
                    else win.showContact(rows[win.currentIndex]);
                }
                e.accepted = true;
            }
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
                    : ""   // the list: its title is the window's own, not repeated
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
                visible: win.mode === "list" && !win.showDuplicates && win.source === "local"
                text: win.selecting ? Tr.t("Cancel selection") : Tr.t("Select…")
                flat: true
                checked: win.selecting
                Accessible.name: win.selecting ? Tr.t("Cancel selecting contacts") : Tr.t("Select several contacts")
                onClicked: win.toggleSelecting()
            }
            Button {
                visible: win.mode === "list" && !win.showDuplicates
                text: Tr.t("New contact")
                kind: "primary"
                enabled: win.source === "local"
                onClicked: win.newContact()
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
                        favorite: !!c.favorite, avatar: win.avatarPath || c.avatar || "",
                        birthday: win.editBirthday.trim(), addresses: win.editAddresses,
                        org: win.editOrg.trim(), role: win.editRole.trim(),
                        urls: win.editUrls.split(/\n+/).map(s => s.trim()).filter(s => s),
                        note: win.editNote };
                    if (win.mode === "add") Contacts.add(win.editName, win.editPhone, win.editEmail, groups, detail);
                    else Contacts.edit(win.editUid, win.editName, win.editPhone, win.editEmail, groups, detail);
                    win.mode = "list";
                }
            }
        }

        // ---- edit form ----
        Flickable {
            visible: win.mode === "add" || win.mode === "edit"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: editForm.implicitHeight
            ColumnLayout {
                id: editForm
                width: parent.width
                spacing: Theme.px(6)

            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Full name")
                label: Tr.t("Full name")
                text: win.editName
                onTextChanged: win.editName = text
            }
            Text { text: Tr.t("Phone numbers"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Repeater {
                model: win.editPhones
                RowLayout {
                    required property int index
                    required property var modelData
                    property int row: index
                    property var phone: modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Flow {
                        Layout.preferredWidth: Theme.px(216)
                        spacing: Theme.px(2)
                        Repeater {
                            model: win.phoneTypes
                            Choice {
                                required property var modelData
                                text: modelData[1]
                                selected: win.phoneType(phone.type) === modelData[0]
                                Accessible.name: "Phone " + (row + 1) + ", type " + modelData[1]
                                onClicked: win.setPhone(row, "type", modelData[0])
                            }
                        }
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: modelData.number || ""
                        placeholder: Tr.t("Phone number")
                        label: Tr.t("Phone number %1", index + 1)
                        onTextChanged: win.setPhone(index, "number", text)
                    }
                    IconButton {
                        size: Theme.px(24); icon: "list-remove"; tip: Tr.t("Remove phone %1", index + 1)
                        accessibleName: tip
                        onClicked: { const rows = win.editPhones.slice(); rows.splice(index, 1); win.editPhones = rows; }
                    }
                }
            }
            Button {
                text: Tr.t("Add phone"); flat: true
                Accessible.name: Tr.t("Add another phone number")
                onClicked: win.editPhones = win.editPhones.concat([{ type: "mobile", number: "" }])
            }
            Text { text: Tr.t("Email addresses"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Repeater {
                model: win.editEmails
                RowLayout {
                    required property int index
                    required property var modelData
                    property int row: index
                    property var email: modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Flow {
                        Layout.preferredWidth: Theme.px(216)
                        spacing: Theme.px(2)
                        Repeater {
                            model: win.phoneTypes
                            Choice {
                                required property var modelData
                                text: modelData[1]
                                selected: win.emailType(email.type) === modelData[0]
                                Accessible.name: "Email " + (row + 1) + ", type " + modelData[1]
                                onClicked: win.setEmail(row, "type", modelData[0])
                            }
                        }
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: modelData.address || ""
                        placeholder: Tr.t("Email address")
                        label: "Email address " + (index + 1)
                        onTextChanged: win.setEmail(index, "address", text)
                    }
                    IconButton {
                        size: Theme.px(24); icon: "list-remove"; tip: "Remove email " + (index + 1)
                        accessibleName: tip
                        onClicked: { const rows = win.editEmails.slice(); rows.splice(index, 1); win.editEmails = rows; }
                    }
                }
            }
            Button {
                text: Tr.t("Add email"); flat: true
                Accessible.name: "Add another email address"
                onClicked: win.editEmails = win.editEmails.concat([{ type: "home", address: "" }])
            }
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
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Birthday, year-month-day")
                label: Tr.t("Birthday")
                text: win.editBirthday
                error: text !== "" && !/^\d{4}-\d{2}-\d{2}$|^--\d{2}-\d{2}$/.test(text.trim())
                    ? Tr.t("Use year-month-day, or month-day") : ""
                onTextChanged: win.editBirthday = text
            }
            Text { text: Tr.t("Address"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
            Repeater {
                model: win.editAddresses
                RowLayout {
                    required property int index
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    TextField {
                        Layout.fillWidth: true
                        placeholder: Tr.t("Street")
                        label: Tr.t("Street address %1", index + 1)
                        text: modelData.street || ""
                        onTextChanged: win.setAddress(index, "street", text)
                    }
                    TextField {
                        Layout.fillWidth: true
                        placeholder: Tr.t("City")
                        label: Tr.t("City %1", index + 1)
                        text: modelData.locality || ""
                        onTextChanged: win.setAddress(index, "locality", text)
                    }
                    IconButton {
                        size: Theme.px(24); icon: "list-remove"
                        tip: Tr.t("Remove address %1", index + 1)
                        accessibleName: tip
                        onClicked: { const rows = win.editAddresses.slice(); rows.splice(index, 1); win.editAddresses = rows; }
                    }
                }
            }
            Button {
                text: Tr.t("Add address"); flat: true
                Accessible.name: Tr.t("Add another address")
                onClicked: win.editAddresses = win.editAddresses.concat([{ type: "home", street: "", locality: "", region: "", code: "", country: "" }])
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Organisation")
                label: Tr.t("Organisation")
                text: win.editOrg
                onTextChanged: win.editOrg = text
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Role")
                label: Tr.t("Role")
                text: win.editRole
                onTextChanged: win.editRole = text
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Websites, one per line")
                label: Tr.t("Websites")
                text: win.editUrls
                onTextChanged: win.editUrls = text
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Note")
                label: Tr.t("Note")
                text: win.editNote
                onTextChanged: win.editNote = text
            }
            Text {
                visible: Contacts.error !== ""
                text: Contacts.error
                color: Theme.red
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
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
                delegate: ListRow {
                    required property var modelData
                    width: dupList.width
                    icon: "contact-new"
                    title: (Contacts.contacts.find(c => c.uid === modelData[0]) || {}).name || "—"
                    subtitle: (Contacts.contacts.find(c => c.uid === modelData[1]) || {}).name || "—"
                    // the heading says a row click merges; KeyFocus comes from ListRow
                    onClicked: Contacts.merge(modelData[0], modelData[1])
                    Button {
                        text: Tr.t("Merge")
                        kind: "outline"
                        onClicked: Contacts.merge(modelData[0], modelData[1])
                    }
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
                text: Tr.t("Undo last merge")
                flat: true
                enabled: !!Contacts.lastMerge
                onClicked: Contacts.undoMerge()
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
            SearchField {
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
            Choice {
                text: Tr.t("My contacts")
                selected: win.source === "local"
                Accessible.name: Tr.t("Show my contacts")
                onClicked: { win.source = "local"; win.selecting = false; win.chosen = []; win.currentIndex = -1; }
            }
            Choice {
                text: Tr.t("From the phone")
                selected: win.source === "phone"
                Accessible.name: Tr.t("Show contacts from the phone")
                onClicked: { win.source = "phone"; win.selecting = false; win.chosen = []; win.currentIndex = -1; Contacts.refreshPhone(); }
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
                model: [Tr.t("All"), Tr.t("Favourites"), Tr.t("No phone"), Tr.t("No email")].concat(Contacts.allGroups.slice(1))
                Choice {
                    required property string modelData
                    text: modelData + "  " + Contacts.countInList(modelData)
                    selected: win.groupFilter === modelData
                    onClicked: win.groupFilter = modelData
                }
            }
        }

        // ---- one action for all chosen cards ----
        RowLayout {
            visible: win.mode === "list" && !win.showDuplicates && win.source === "local" && win.selecting
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Text {
                text: Tr.t("%1 chosen", win.chosen.length)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
            }
            Item { Layout.fillWidth: true }
            Button {
                text: Tr.t("Export chosen"); flat: true
                enabled: win.chosen.length > 0
                Accessible.name: Tr.t("Export the chosen contacts")
                onClicked: FilePicker.open({ mode: "save", title: Tr.t("Export contacts"), defaultName: "contacts.vcf",
                    filters: ["vcf"], onPicked: paths => { if (paths.length) Contacts.exportAll(paths[0], win.chosen); } })
            }
            ConfirmButton {
                id: deleteChosen
                implicitWidth: Math.max(Theme.touchTarget, deleteChosen.armedText.length * 8 + 28)
                implicitHeight: Math.max(Theme.px(36), Theme.touchTarget)
                text: Tr.t("Delete chosen")
                armedText: Tr.t("Tap again to delete")
                kind: deleteChosen.armed ? "danger" : "plain"
                enabled: win.chosen.length > 0
                Accessible.name: Tr.t("Delete chosen contacts")
                onConfirmed: {
                    Contacts.removeMany(win.chosen);
                    win.chosen = [];
                    win.selecting = false;
                }
            }
            Button {
                text: Tr.t("Done"); flat: true
                Accessible.name: Tr.t("Stop selecting contacts")
                onClicked: win.toggleSelecting()
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
            model: win.visibleContacts()
            currentIndex: win.currentIndex
            Accessible.role: Accessible.List
            Accessible.name: Tr.t("Contacts")
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
                    z: 2                 // the icon actions must win over the row's z:1 click catcher
                    Rectangle {
                        visible: win.selecting && win.source === "local"
                        width: Math.max(Theme.px(22), Theme.touchTarget)
                        height: width
                        radius: width / 2
                        color: win.chosen.indexOf(modelData.uid) >= 0 ? Theme.accent : "transparent"
                        border.width: 2
                        border.color: Theme.dim
                        Icon {
                            anchors.centerIn: parent
                            visible: win.chosen.indexOf(modelData.uid) >= 0
                            name: "object-select"; size: Theme.px(14); color: Theme.accentInk
                        }
                        Accessible.role: Accessible.CheckBox
                        Accessible.checked: win.chosen.indexOf(modelData.uid) >= 0
                        Accessible.name: Tr.t("Select") + " " + (modelData.name || Tr.t("Unnamed"))
                        Accessible.onToggleAction: win.toggleSelected(modelData.uid)
                        // a second KeyFocus in the row would steal the row's own key path
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.toggleSelected(modelData.uid) }
                    }
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
                        icon: "mail-unread"
                        accessibleName: Tr.t("Message %1", modelData.name || "")
                        tip: Tr.t("Message %1", modelData.name || "")
                        onClicked: win.messageContact(modelData)
                    }
                    IconButton {
                        visible: win.source === "local"
                        size: Theme.px(28)
                        icon: modelData.favorite ? "starred" : "non-starred"
                        tip: modelData.favorite ? "Remove from favourites" : "Add to favourites"
                        onClicked: Contacts.toggleFavorite(modelData.uid)
                    }
                    IconButton {
                        visible: win.source === "local"
                        size: Theme.px(28)
                        icon: modelData.uid === Contacts.myUid ? "starred" : "avatar-default"
                        tip: modelData.uid === Contacts.myUid ? Tr.t("This is you") : Tr.t("This is me")
                        onClicked: Contacts.toggleMe(modelData.uid)
                    }
                    IconButton {
                        visible: win.source === "local"
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
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name || Tr.t("Unnamed")
                Accessible.onPressAction: win.showContact(modelData)
                KeyFocus { onActivated: win.showContact(modelData) }
            }
            EmptyState {
                anchors.centerIn: parent
                visible: list.count === 0 && !Contacts.busy && !Contacts.phoneBusy
                icon: "contact-new"
                title: win.source === "phone" ? Tr.t("No contacts on the phone")
                    : Contacts.query !== "" ? Tr.t("No matches for %1", Contacts.query)
                    : win.groupFilter === Tr.t("Favourites") ? Tr.t("No favourites yet") : Tr.t("No contacts yet")
                subtitle: win.source === "phone" ? Tr.t("Connect a phone to see its contacts here")
                    : Contacts.query !== "" ? Tr.t("Try a different name or number")
                    : win.groupFilter === Tr.t("Favourites") ? Tr.t("Star a contact to see it here")
                    : Tr.t("Add one above, or import a .vcf file")
            }
        }

        // ---- footer ----
        Text {
            visible: Contacts.notice !== ""
            Layout.fillWidth: true
            text: Contacts.notice
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            Accessible.role: Accessible.StatusBar
            Accessible.name: Contacts.notice
        }
        Text {
            visible: Contacts.error !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Contacts.error
            color: Theme.red
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            Accessible.role: Accessible.StatusBar
            Accessible.name: Contacts.error
        }
        Text {
            visible: win.mode === "list" && !win.showDuplicates
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: win.source === "phone"
                ? Tr.t("%1 phone contact%2 · Esc closes", Contacts.phoneContacts.length, Contacts.phoneContacts.length === 1 ? "" : "s")
                : Tr.t("%1 contact%2 · Esc closes", Contacts.contacts.length, Contacts.contacts.length === 1 ? "" : "s")
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
                property var c: (win.source === "phone" ? Contacts.phoneContacts : Contacts.contacts).find(x => x.uid === win.detailUid) || {}
                property bool isPhone: win.source === "phone"
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
                    // phone rows carry `numbers`; local cards carry typed `phones`
                    model: detailCol.c.phones || (detailCol.c.numbers || []).map(n => ({ type: "cell", number: n }))
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Icon { name: "call-start"; size: Theme.px(18); color: Theme.dim }
                        Text {
                            Layout.fillWidth: true
                            text: win.phoneType(modelData.type) + ": " + (modelData.number || "")
                            Accessible.name: win.phoneType(modelData.type) + " phone: " + (modelData.number || "")
                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; elide: Text.ElideRight
                        }
                        IconButton {
                            size: Theme.px(24)
                            icon: "edit-copy"
                            tip: Tr.t("Copy number")
                            onClicked: win.copyText(modelData.number)
                        }
                        Button { text: Tr.t("Call"); flat: true; onClicked: win.openExternal("tel:" + (modelData.number || "")) }
                    }
                }
                Repeater {
                    model: (detailCol.c.emails || []).map(e => typeof e === "string" ? { type: "home", address: e } : e)
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Icon { name: "mail-unread"; size: Theme.px(18); color: Theme.dim }
                        Text {
                            Layout.fillWidth: true
                            text: win.emailType(modelData.type) + ": " + (modelData.address || "")
                            Accessible.name: win.emailType(modelData.type) + " email: " + (modelData.address || "")
                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale; elide: Text.ElideRight
                        }
                        IconButton {
                            size: Theme.px(24)
                            icon: "edit-copy"
                            tip: Tr.t("Copy address")
                            onClicked: win.copyText(modelData.address)
                        }
                        Button { text: Tr.t("Mail"); flat: true; onClicked: win.openExternal("mailto:" + (modelData.address || "")) }
                    }
                }
                Button {
                    text: Tr.t("Copy name")
                    flat: true
                    enabled: !!((detailCol.c.name || ""))
                    onClicked: win.copyText(detailCol.c.name)
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
                    Button { text: Tr.t("QR code"); flat: true; onClicked: Contacts.vcard(win.detailUid, detailCol.c.name || "Contact") }
                    Button {
                        text: Tr.t("Message…")
                        flat: true
                        enabled: (detailCol.c.phones || []).length > 0
                        onClicked: win.messageContact(detailCol.c)
                    }
                    Button {
                        text: Tr.t("Add to note")
                        flat: true
                        Accessible.name: Tr.t("Add this contact to a note")
                        enabled: !!(detailCol.c.name)
                        onClicked: win.contactToNote(detailCol.c)
                    }
                    Button { Layout.fillWidth: true; text: Tr.t("Close"); onClicked: win.showDetail = false }
                    Button {
                        visible: detailCol.isPhone
                        Layout.fillWidth: true; text: Tr.t("Save here"); kind: "primary"
                        Accessible.name: Tr.t("Save this phone contact to my contacts")
                        onClicked: win.savePhoneContact(detailCol.c)
                    }
                    Button {
                        visible: !detailCol.isPhone
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
                            win.editBirthday = c.birthday || "";
                            win.editAddresses = (c.addresses || []).map(x => Object.assign({}, x));
                            win.editOrg = c.org || "";
                            win.editRole = c.role || "";
                            win.editUrls = (c.urls || []).join("\n");
                            win.editNote = c.note || "";
                            win.avatarPath = c.avatar || "";
                            win.showGroupField = (c.groups || []).length > 0;
                        }
                    }
                }
            }
        }
    }
}
