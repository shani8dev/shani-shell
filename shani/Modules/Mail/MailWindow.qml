// Mail: an IMAP reader (or MailHog, for development). Four panes — the
// folders, the message list, the message being read, and a small compose form.
// bridge/mail.py does the talking; the window is only a view.
//
// The extras here answer what Thunderbird, Evolution and Apple Mail all do:
// conversations, quick filters and search operators, multi-select with undo,
// keyboard navigation, live unread badges, drafts, and honest empty/offline
// states. All of it stays view-side — the bridge contract is unchanged.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Mail"
    visible: Ui.mail
    onGone: Ui.mail = false
    implicitWidth: Theme.px(1080)
    implicitHeight: Theme.px(680)
    shortcutSearch: searchField.input   // Ctrl+F focuses the folder's search
    shortcutRefresh: win.refresh        // Ctrl+R re-reads the folder
    function refresh() { Mail.refresh(); }
    // refresh lives in AppWindow's header tools, not in the folders pane
    tools: [
        IconButton { icon: "view-refresh"; tip: Tr.t("Refresh"); size: Theme.px(26); on: Mail.busy; onClicked: win.refresh() }
    ]

    // ---- view state ---------------------------------------------------------
    property bool threaded: false          // group messages into conversations
    property var expandedThreads: []       // conversation keys the person opened
    property bool filterUnread: false      // quick filter: unread only
    property bool filterStarred: false     // quick filter: starred only
    property string filterText: ""         // the search box, incl. from:/subject:/is: operators
    property var selectedUids: []          // multi-select for bulk actions
    property bool selecting: false
    property var lastBulk: ({})            // { kind, uids } of the last bulk action, for undo
    property bool subjectWarning: false    // send was pressed with an empty subject
    property int cursor: 0

    property bool starred: (Mail.messages.find(m => m.uid === Mail.openUid) || {}).starred || false
    // the list is a view over Mail.messages, sorted here rather than asking the
    // server for a new order: the bridge already hands us the whole folder
    property string sortField: "date"
    property bool sortNewest: true

    // "Re: fwd: Hello" and "Hello" are one conversation: strip the prefixes.
    function conversationKey(row) {
        return String(row.subject || "").trim().replace(/^((re|fw|fwd)\s*:\s*)+/i, "").toLowerCase();
    }

    function hasOperators(t) { return /\b(from|subject|is):/i.test(String(t || "")); }

    // from:, subject: and is:unread|read|starred refine the loaded list locally,
    // the way a quick-filter bar does, without another IMAP round trip.
    function matchesOperators(row, text) {
        const parts = String(text || "").trim().toLowerCase().split(/\s+/).filter(Boolean);
        return parts.every(part => {
            const c = part.indexOf(":");
            if (c < 1) return (String(row.subject || "") + " " + String(row.from || "")
                + " " + String(row.snippet || "")).toLowerCase().indexOf(part) >= 0;
            const key = part.slice(0, c), val = part.slice(c + 1);
            if (key === "from") return String(row.from || "").toLowerCase().indexOf(val) >= 0;
            if (key === "subject") return String(row.subject || "").toLowerCase().indexOf(val) >= 0;
            if (key === "is") {
                if (val === "unread") return !!row.unread;
                if (val === "read") return !row.unread;
                if (val === "starred") return !!row.starred;
            }
            return true;
        });
    }

    function passesFilters(row) {
        if (win.filterUnread && !row.unread) return false;
        if (win.filterStarred && !row.starred) return false;
        if (win.hasOperators(win.filterText) && !win.matchesOperators(row, win.filterText)) return false;
        return true;
    }

    function sortedMessages() {
        const rows = Mail.messages.filter(win.passesFilters);
        const key = row => win.sortField === "subject" ? String(row.subject || "").toLowerCase()
            : win.sortField === "from" ? String(row.from || "").toLowerCase()
            : (Date.parse(row.date) || 0);
        rows.sort((a, b) => {
            const ka = key(a), kb = key(b);
            const c = typeof ka === "number" && typeof kb === "number" ? ka - kb : String(ka).localeCompare(String(kb));
            return win.sortNewest ? -c : c;
        });
        return rows;
    }

    // A flat model for the ListView: either the messages, or one summary row
    // per conversation with the individual messages spliced in when expanded.
    function visibleMessages() {
        const rows = win.sortedMessages();
        if (!win.threaded) return rows;
        const groups = {}, order = [];
        rows.forEach(r => {
            const k = win.conversationKey(r) || ("\u0000" + r.uid);
            if (!groups[k]) { groups[k] = []; order.push(k); }
            groups[k].push(r);
        });
        const out = [];
        order.forEach(k => {
            const g = groups[k];
            if (g.length < 2) { out.push(g[0]); return; }
            out.push({
                uid: g[0].uid, isThread: true, threadKey: k,
                threadUids: g.map(m => m.uid), subject: g[0].subject, from: g[0].from,
                date: g[0].date, snippet: g[0].snippet,
                unread: g.some(m => m.unread), starred: g.some(m => m.starred),
                count: g.length, unreadCount: g.filter(m => m.unread).length
            });
            if (win.expandedThreads.indexOf(k) >= 0) g.forEach(m => {
                out.push({ uid: m.uid, inThread: true, subject: m.subject, from: m.from,
                    date: m.date, snippet: m.snippet, unread: m.unread, starred: m.starred });
            });
        });
        return out;
    }

    function toggleThread(key) {
        const i = win.expandedThreads.indexOf(key);
        win.expandedThreads = i >= 0 ? win.expandedThreads.filter(k => k !== key)
                                     : win.expandedThreads.concat([key]);
    }

    function markAllRead() {
        Mail.messages.forEach(m => { if (m.unread) Mail.markRead(m.uid); });
        Mail.refresh();
    }

    // ---- selection and bulk actions ----------------------------------------
    function toggleSelect(uid) {
        const i = win.selectedUids.indexOf(uid);
        win.selectedUids = i >= 0 ? win.selectedUids.filter(u => u !== uid) : win.selectedUids.concat([uid]);
    }
    function clearSelection() { if (win.selectedUids.length) win.selectedUids = []; }
    function selectAll() { win.selectedUids = Mail.messages.filter(win.passesFilters).map(m => m.uid); }

    function bulk(kind) {
        const uids = win.selectedUids.slice();
        if (!uids.length) return;
        win.lastBulk = { kind: kind, uids: uids };
        uids.forEach(uid => {
            if (kind === "read") Mail.markRead(uid);
            else if (kind === "star") Mail.flag(uid, "\\Flagged", true);
            else if (kind === "unstar") Mail.flag(uid, "\\Flagged", false);
            else if (kind === "archive") Mail.archive(uid);
            else if (kind === "delete") Mail.remove(uid);
        });
        win.clearSelection();
    }
    // Move and delete cannot be reversed by the bridge (there is no undelete),
    // so only flag/read changes offer undo; the bar says so for the others.
    function undoAvailable() {
        return ["read", "star", "unstar"].indexOf(String(win.lastBulk.kind || "")) >= 0;
    }
    function undoBulk() {
        const a = win.lastBulk;
        if (!win.undoAvailable()) return;
        if (a.kind === "read") a.uids.forEach(uid => Mail.markUnread(uid));
        else if (a.kind === "star") a.uids.forEach(uid => Mail.flag(uid, "\\Flagged", false));
        else if (a.kind === "unstar") a.uids.forEach(uid => Mail.flag(uid, "\\Flagged", true));
        win.lastBulk = {};
    }

    function clearFilters() {
        win.filterUnread = false;
        win.filterStarred = false;
        win.filterText = "";
        searchField.text = "";
        if (Mail.query !== "") Mail.search("");
    }

    function applySearch(t) {
        win.filterText = String(t || "").trim();
        // Operators refine the loaded list here; plain words go to IMAP SEARCH.
        if (win.hasOperators(win.filterText)) Mail.query = win.filterText;
        else Mail.search(win.filterText);
    }

    function saveAttachment(index, name) {
        FilePicker.open({
            mode: "save",
            title: Tr.t("Save attachment"),
            defaultName: name || "attachment",
            onPicked: paths => { if (paths && paths.length) Mail.saveAttachment(Mail.openUid, index, paths[0]); }
        });
    }

    // ---- keyboard navigation ------------------------------------------------
    function moveCursor(delta) {
        const rows = win.visibleMessages();
        if (!rows.length) return;
        const from = list.currentIndex < 0 ? 0 : list.currentIndex;
        const next = Math.max(0, Math.min(rows.length - 1, from + delta));
        list.currentIndex = next;
        win.cursor = next;
        const row = rows[next];
        if (row && !row.isThread) Mail.read(row.uid);
    }
    function openCursor() {
        const rows = win.visibleMessages();
        const row = rows[list.currentIndex];
        if (!row) return;
        if (row.isThread) win.toggleThread(row.threadKey);
        else Mail.read(row.uid);
    }
    function nextUnread(dir) {
        const rows = win.visibleMessages();
        if (!rows.length) return;
        let i = list.currentIndex < 0 ? 0 : list.currentIndex;
        for (let n = 0; n < rows.length; n++) {
            i = (i + dir + rows.length) % rows.length;
            if (rows[i] && rows[i].unread) { list.currentIndex = i; Mail.read(rows[i].uid); return; }
        }
    }
    function reply() {
        if (!Mail.from) return;
        win.startCompose(Mail.from, win.replySubject(), win.quotedBody());
    }
    function forward() {
        win.startCompose("", "Fwd: " + Mail.subject,
            "\n\n---------- Forwarded message ----------\nFrom: " + Mail.from + "\nSubject: " + Mail.subject + "\n\n" + Mail.body);
    }
    function isTyping() {
        const f = win.activeFocusItem;
        return !!f && (f instanceof TextInput || f instanceof TextEdit);
    }
    // Single-letter shortcuts, as in Thunderbird/Evolution: j/k move, Enter
    // opens, r reply, a archive, s star, u unread, n next unread, c compose,
    // / search, Escape backs out of whatever layer is open.
    function mailKey(e) {
        if (e.key === Qt.Key_Escape) {
            if (sourceView.visible) Mail.source = "";
            else if (compose.visible) win.closeCompose(false);
            else if (win.selectedUids.length) win.clearSelection();
            else if (win.filterUnread || win.filterStarred || win.filterText) win.clearFilters();
            else return false;
            return true;
        }
        if (win.isTyping()) return false;
        if (e.key === Qt.Key_Slash) { searchField.input.forceActiveFocus(); return true; }
        if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { win.moveCursor(1); return true; }
        if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { win.moveCursor(-1); return true; }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.openCursor(); return true; }
        if (e.key === Qt.Key_C) { win.startCompose("", "", ""); return true; }
        if (!Mail.openUid) return false;
        if (e.key === Qt.Key_R) { win.reply(); return true; }
        if (e.key === Qt.Key_A) { Mail.archive(Mail.openUid); return true; }
        if (e.key === Qt.Key_S) { Mail.flag(Mail.openUid, "\\Flagged", !win.starred); return true; }
        if (e.key === Qt.Key_U) { Mail.markUnread(Mail.openUid); return true; }
        if (e.key === Qt.Key_N) { win.nextUnread(1); return true; }
        return false;
    }
    Keys.onPressed: e => { if (win.mailKey(e)) e.accepted = true; }

    // ---- compose ------------------------------------------------------------
    function startCompose(to, subject, body) {
        compose.visible = true;
        compose.to = to;
        toBox.text = to;
        ccBox.text = "";
        bccBox.text = "";
        subBox.text = subject;
        bodyBox.text = body;
        win.subjectWarning = false;
        toBox.forceActiveFocus();
    }
    function closeCompose(sent) {
        compose.visible = false;
        compose.to = "";
        ccBox.text = ""; bccBox.text = ""; subBox.text = ""; bodyBox.text = "";
        win.subjectWarning = false;
        if (sent) Mail.clearDraft();
    }
    function sendCompose() {
        if (toBox.text.trim() === "") return;
        if (subBox.text.trim() === "") { win.subjectWarning = true; return; }
        Mail.send(toBox.text.trim(), subBox.text, bodyBox.text, ccBox.text.trim(), bccBox.text.trim());
        win.closeCompose(true);
    }
    // A second press after the warning means "yes, send it without a subject".
    function forceSend() {
        if (toBox.text.trim() === "") return;
        Mail.send(toBox.text.trim(), subBox.text, bodyBox.text, ccBox.text.trim(), bccBox.text.trim());
        win.closeCompose(true);
    }
    function saveDraft() {
        Mail.saveDraft({ to: toBox.text.trim(), cc: ccBox.text.trim(), bcc: bccBox.text.trim(),
            subject: subBox.text, body: bodyBox.text });
        win.closeCompose(false);
    }
    function resumeDraft() {
        const d = Mail.draft || {};
        win.startCompose(d.to || "", d.subject || "", d.body || "");
        ccBox.text = d.cc || "";
        bccBox.text = d.bcc || "";
    }
    function replySubject() {
        const s = String(Mail.subject || "");
        return /^re:/i.test(s.trim()) ? s : "Re: " + s;
    }
    function quotedBody() {
        return "\n\nOn " + Mail.when(Mail.date) + ", " + Mail.from + " wrote:\n> "
            + String(Mail.body || "").replace(/\n/g, "\n> ");
    }

    // ---- status note and offline/error banner -------------------------------
    Text {
        anchors { top: parent.top; right: parent.right; margins: Theme.px(12) }
        z: 20
        visible: Mail.note !== "" && !Mail.error
        text: Mail.note
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
        Timer { interval: 5000; onTriggered: Mail.note = ""; running: parent.visible }
    }
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.px(10) }
        z: 25
        visible: Mail.error
        radius: Theme.radiusSmall
        color: Theme.alpha(Theme.danger, 0.16)
        border.width: 1
        border.color: Theme.alpha(Theme.danger, 0.5)
        RowLayout {
            anchors { fill: parent; margins: Theme.px(8) }
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("Offline or mail server unavailable — check your connection")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
            Button {
                text: Tr.t("Retry")
                flat: true
                onClicked: { Mail.error = false; Mail.refresh(); }
            }
            IconButton {
                icon: "window-close"; tip: Tr.t("Dismiss"); size: Theme.px(22)
                onClicked: Mail.error = false
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(10)
        spacing: Theme.px(10)

        // ---- folders --------------------------------------------------------
        Rectangle {
            Layout.preferredWidth: Theme.px(200)
            Layout.fillHeight: true
            radius: Theme.radius
            color: Theme.alpha(Theme.text, 0.035)
            border.width: 1
            border.color: Theme.stroke

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(10)
                spacing: Theme.px(8)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Text { text: Tr.t("Mail"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    TextField {
                        id: toField
                        Layout.fillWidth: true
                        placeholder: Tr.t("To…")
                        label: Tr.t("New message recipient")
                    }
                    Button { text: Tr.t("Write"); enabled: toField.text.trim() !== ""; onClicked: { win.startCompose(toField.text.trim(), "", ""); toField.text = "" } }
                }
                Button {
                    text: Tr.t("Resume draft")
                    flat: true
                    visible: !!Mail.draft
                    onClicked: win.resumeDraft()
                }
                SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Search the mail…")
                    label: Tr.t("Search mail")
                    onTextChanged: if (text.trim() === "" && (Mail.query !== "" || win.filterText !== "")) win.clearFilters()
                    Connections { target: searchField.input; function onAccepted() { win.applySearch(searchField.text) } }
                }
                ListView {
                    id: folderList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: Mail.folders
                    delegate: ListRow {
                        required property var modelData
                        width: ListView.view.width
                        icon: modelData.unread > 0 ? "mail-unread" : "mail-read"
                        title: modelData.name
                        subtitle: modelData.unread > 0 ? Tr.t("%1 unread", modelData.unread) : ""
                        selected: Mail.folder === modelData.name
                        Accessible.name: modelData.name + (modelData.unread > 0 ? ", " + Tr.t("%1 unread", modelData.unread) : "")
                        onClicked: Mail.open(modelData.name)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: Mail.folders.length === 0 && !Mail.busy
                    text: Mail.kind === "imap" ? Tr.t("No account set up yet") : Tr.t("No mail yet")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }

        // ---- the message list -----------------------------------------------
        ColumnLayout {
            Layout.preferredWidth: Theme.px(300)
            Layout.fillHeight: true
            spacing: Theme.px(4)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Text {
                    Layout.fillWidth: true
                    text: Mail.folder
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Button {
                    text: Tr.t("Mark all read")
                    flat: true
                    enabled: Mail.messages.some(m => m.unread)
                    onClicked: win.markAllRead()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Repeater {
                    model: [["date", Tr.t("Date")], ["from", Tr.t("From")], ["subject", Tr.t("Subject")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.sortField === modelData[0]
                        onClicked: win.sortField = modelData[0]
                    }
                }
                Button {
                    text: win.sortField === "date"
                        ? (win.sortNewest ? Tr.t("Newest") : Tr.t("Oldest"))
                        : (win.sortNewest ? Tr.t("Z–A") : Tr.t("A–Z"))
                    flat: true
                    onClicked: win.sortNewest = !win.sortNewest
                }
            }
            // quick filters and conversation view, as in Thunderbird/Evolution
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Choice { text: Tr.t("Unread"); selected: win.filterUnread; onClicked: win.filterUnread = !win.filterUnread }
                Choice { text: Tr.t("Starred"); selected: win.filterStarred; onClicked: win.filterStarred = !win.filterStarred }
                Choice { text: Tr.t("Threads"); selected: win.threaded; onClicked: win.threaded = !win.threaded }
                Item { Layout.fillWidth: true }
                Button {
                    text: Tr.t("Select")
                    flat: true
                    checked: win.selecting
                    onClicked: { win.selecting = !win.selecting; if (!win.selecting) win.clearSelection(); }
                }
            }
            // selection + undo bar: only shown while selecting or just after a
            // bulk action, so the normal list stays clean
            Rectangle {
                Layout.fillWidth: true
                visible: win.selecting || !!win.lastBulk.kind
                radius: Theme.radiusSmall
                color: Theme.alpha(Theme.accent, 0.10)
                implicitHeight: bar.implicitHeight
                RowLayout {
                    id: bar
                    anchors { left: parent.left; right: parent.right; margins: Theme.px(6) }
                    spacing: Theme.px(4)
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: win.selecting ? Tr.t("%1 selected", win.selectedUids.length)
                            : (win.undoAvailable() ? Tr.t("Undo last bulk action") : Tr.t("Archived or deleted — no undo"))
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Button { text: Tr.t("All"); flat: true; visible: win.selecting; onClicked: win.selectAll() }
                    Button { text: Tr.t("Read"); flat: true; visible: win.selecting; enabled: win.selectedUids.length > 0; onClicked: win.bulk("read") }
                    Button { text: Tr.t("Star"); flat: true; visible: win.selecting; enabled: win.selectedUids.length > 0; onClicked: win.bulk("star") }
                    Button { text: Tr.t("Archive"); flat: true; visible: win.selecting; enabled: win.selectedUids.length > 0; onClicked: win.bulk("archive") }
                    Button { text: Tr.t("Delete"); flat: true; kind: "danger"; visible: win.selecting; enabled: win.selectedUids.length > 0; onClicked: win.bulk("delete") }
                    Button { text: Tr.t("Undo"); flat: true; visible: !win.selecting && win.undoAvailable(); onClicked: win.undoBulk() }
                    Button { text: Tr.t("Done"); flat: true; visible: win.selecting; onClicked: { win.selecting = false; win.clearSelection(); } }
                }
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: win.visibleMessages()
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: ListRow {
                    required property var modelData
                    width: ListView.view.width
                    icon: modelData.isThread ? "view-list" : (modelData.unread ? "mail-unread" : "mail-read")
                    title: (modelData.inThread ? "    " : "") + modelData.subject
                    subtitle: (win.selectedUids.indexOf(modelData.uid) >= 0 ? "✓ " : "")
                        + (modelData.isThread ? Tr.t("%1 messages", modelData.count)
                            + (modelData.unreadCount ? " · " + modelData.unreadCount + " new" : "") + "  ·  " : "")
                        + Mail.when(modelData.date) + (modelData.from ? "  ·  " + modelData.from : "")
                        + (modelData.snippet ? "\n" + modelData.snippet : "")
                    trailing: modelData.starred ? "★" : ""
                    selected: Mail.openUid === modelData.uid || win.selectedUids.indexOf(modelData.uid) >= 0
                    Accessible.name: (modelData.unread ? Tr.t("Unread") + ", " : "")
                        + (modelData.isThread ? Tr.t("Conversation, %1 messages", modelData.count) + ", " : "")
                        + String(modelData.subject || "")
                    onClicked: {
                        if (win.selecting) win.toggleSelect(modelData.uid);
                        else if (modelData.isThread) win.toggleThread(modelData.threadKey);
                        else Mail.read(modelData.uid);
                    }
                }
            }
            BusyNote {
                Layout.fillWidth: true
                visible: Mail.busy && Mail.messages.length === 0
                note: Tr.t("Loading mail…")
            }
            EmptyState {
                visible: !Mail.busy && win.visibleMessages().length === 0
                icon: Mail.query !== "" ? "edit-find" : Mail.kind === "" ? "preferences-system" : "mail-read"
                title: Mail.query !== "" ? Tr.t("No matches for %1", Mail.query)
                    : Mail.kind === "" ? Tr.t("No mail account set up") : Tr.t("Nothing in this folder")
                subtitle: Mail.kind === "" ? Tr.t("Set up an account to start reading mail")
                    : (win.filterUnread || win.filterStarred) ? Tr.t("Try clearing the quick filters") : ""
                actionText: (win.filterUnread || win.filterStarred) ? Tr.t("Clear filters") : ""
                onAction: win.clearFilters()
            }
        }

        // ---- the message being read -----------------------------------------
        Flickable {
            id: reader
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: body.height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: body
                width: reader.width
                spacing: Theme.px(10)

                Text {
                    Layout.fillWidth: true
                    visible: Mail.subject === ""
                    text: Tr.t("Pick a message")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                Text {
                    Layout.fillWidth: true
                    visible: Mail.subject !== ""
                    text: Mail.subject
                    textFormat: Text.PlainText
                    color: Theme.text
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(20) * Theme.fontScale
                    font.weight: Font.DemiBold
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: Tr.t("Subject") + ": " + text
                }
                Text {
                    Layout.fillWidth: true
                    visible: Mail.from !== ""
                    text: Mail.from
                    textFormat: Text.PlainText
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Text {
                    Layout.fillWidth: true
                    visible: Mail.body !== "" && !Mail.showHtml
                    text: Mail.body
                    color: Theme.text
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                }
                // the message as it was sent: Qt's TextDocument renders a subset
                // of HTML, and the bridge has already taken out everything that
                // reaches outside the message (scripts, remote images, handlers)
                Text {
                    Layout.fillWidth: true
                    visible: Mail.showHtml && Mail.html !== ""
                    textFormat: Text.RichText
                    text: Mail.html
                    color: Theme.text
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: Mail.html !== ""
                    spacing: Theme.px(6)
                    Button {
                        text: Tr.t("Plain text")
                        flat: true
                        visible: Mail.showHtml
                        onClicked: Mail.showHtml = false
                    }
                    Button {
                        text: Tr.t("Original formatting")
                        flat: true
                        visible: !Mail.showHtml
                        onClicked: Mail.showHtml = true
                    }
                    Choice {
                        text: Tr.t("Load images")
                        selected: Mail.remoteImages
                        onClicked: Mail.setRemoteImages(!Mail.remoteImages)
                    }
                    Item { Layout.fillWidth: true }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Mail.attachments.length > 0
                    spacing: Theme.px(2)
                    Repeater {
                        model: Mail.attachments
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "mail-attachment"
                            title: modelData.name || Tr.t("attachment")
                            subtitle: modelData.size > 0 ? Mail.size(modelData.size) : (modelData.type || "")
                            interactive: false
                            IconButton {
                                icon: "document-save"
                                size: Theme.px(22)
                                tip: Tr.t("Save attachment")
                                onClicked: win.saveAttachment(index, modelData.name)
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: Mail.openUid !== ""
                    spacing: Theme.px(6)
                    Button {
                        text: Tr.t("Reply")
                        flat: true
                        enabled: Mail.from !== ""
                        onClicked: win.reply()
                    }
                    Button {
                        text: Tr.t("Forward")
                        flat: true
                        onClicked: win.forward()
                    }
                    Button {
                        text: Tr.t("Unread")
                        flat: true
                        onClicked: Mail.markUnread(Mail.openUid)
                    }
                    Button {
                        text: win.starred ? Tr.t("Unstar") : Tr.t("Star")
                        flat: true
                        checked: win.starred
                        onClicked: Mail.flag(Mail.openUid, "\\Flagged", !win.starred)
                    }
                    Button {
                        text: Tr.t("Archive")
                        flat: true
                        onClicked: Mail.archive(Mail.openUid)
                    }
                    Button {
                        text: Tr.t("View source")
                        flat: true
                        onClicked: Mail.viewSource(Mail.openUid)
                    }
                    Button {
                        text: Tr.t("Delete")
                        kind: "danger"
                        flat: true
                        onClicked: Mail.remove(Mail.openUid)
                    }
                    Item { Layout.fillWidth: true }
                }
                Item { Layout.preferredHeight: 20 }
            }
        }
    }

    // ---- compose ------------------------------------------------------------
    Rectangle {
        id: compose
        visible: false
        property string to: ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, Theme.px(560))
        implicitHeight: col.implicitHeight + 40
        radius: Theme.radiusLarge
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.stroke

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: Theme.px(8)

            Text { text: Tr.t("New message"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(16) * Theme.fontScale; font.weight: Font.DemiBold }
            TextField { id: toBox; Layout.fillWidth: true; placeholder: Tr.t("To…"); label: Tr.t("Recipient"); text: compose.to }
            TextField { id: ccBox; Layout.fillWidth: true; placeholder: Tr.t("Cc…"); label: Tr.t("Cc recipients") }
            TextField { id: bccBox; Layout.fillWidth: true; placeholder: Tr.t("Bcc…"); label: Tr.t("Bcc recipients") }
            TextField { id: subBox; Layout.fillWidth: true; placeholder: Tr.t("Subject…"); label: Tr.t("Subject") }
            Text {
                Layout.fillWidth: true
                visible: win.subjectWarning
                text: Tr.t("No subject — press Send again to send anyway")
                color: Theme.danger
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(160)
                TextArea { id: bodyBox; placeholderText: Tr.t("Write here…"); wrapMode: TextArea.Wrap; textFormat: Text.PlainText }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button {
                    text: win.subjectWarning ? Tr.t("Send anyway") : Tr.t("Send")
                    kind: "primary"
                    enabled: toBox.text.trim() !== ""
                    onClicked: win.subjectWarning ? win.forceSend() : win.sendCompose()
                }
                Button { text: Tr.t("Save draft"); flat: true; enabled: toBox.text.trim() !== "" || subBox.text.trim() !== "" || bodyBox.text.trim() !== ""; onClicked: win.saveDraft() }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: win.closeCompose(false) }
            }
        }
    }

    // ---- the message as it arrived -----------------------------------------
    Rectangle {
        id: sourceView
        visible: Mail.source !== ""
        z: 30
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, Theme.px(760))
        height: Math.min(parent.height - 80, Theme.px(520))
        radius: Theme.radiusLarge
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.stroke

        ColumnLayout {
            anchors { fill: parent; margins: Theme.px(16) }
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Tr.t("Message source")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                IconButton { icon: "window-close"; tip: Tr.t("Close"); size: Theme.px(24); onClicked: Mail.source = "" }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    readOnly: true
                    text: Mail.source
                    wrapMode: TextArea.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }
    }
}
