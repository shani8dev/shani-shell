"""Static checks for the large Mail-client upgrade.

Benchmarked against Thunderbird, Evolution and Apple Mail: conversation view,
quick filters and search operators, multi-select with undo, keyboard navigation,
live unread badges, drafts, a subjectless-send warning, and honest empty/offline
states. Every behaviour is a branch in the two owned QML files; there is no QML
runtime here, so the tests pin the wiring (functions, properties and delegates)
rather than rendering the window.

The bridge contract (bridge/mail.py) is deliberately unchanged: these are all
view-side additions plus careful extensions of the Mail singleton.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW = ROOT / "shani/Modules/Mail/MailWindow.qml"
SERVICE = ROOT / "shani/Services/Mail.qml"

MAIL = WINDOW.read_text(encoding="utf-8")
SERVICE_TEXT = SERVICE.read_text(encoding="utf-8")


def test_conversation_grouping_like_thunderbird_and_apple_mail():
    """Threads collapse to one row with a count; expand to see the messages."""
    assert "property bool threaded: false" in MAIL
    assert "property var expandedThreads: []" in MAIL
    assert "function conversationKey(row)" in MAIL
    assert 'replace(/^((re|fw|fwd)\\s*:\\s*)+/i, "").toLowerCase()' in MAIL
    assert "function sortedMessages()" in MAIL
    assert "function visibleMessages()" in MAIL
    assert "isThread: true, threadKey: k" in MAIL
    assert "threadUids: g.map(m => m.uid)" in MAIL
    assert "unreadCount: g.filter(m => m.unread).length" in MAIL
    assert "function toggleThread(key)" in MAIL
    assert 'text: Tr.t("Threads")' in MAIL
    assert "else if (modelData.isThread) win.toggleThread(modelData.threadKey);" in MAIL
    assert "model: win.visibleMessages()" in MAIL


def test_folder_unread_counts_refresh_when_a_message_is_read():
    """Reading a message updates its row and the folder badge without a re-list."""
    assert "property var folders: []" in SERVICE_TEXT
    assert "function markRead(uid) {" in SERVICE_TEXT
    assert "root.messages.find(m => m.uid === uid)" in SERVICE_TEXT
    assert "root.messages = root.messages.map(" in SERVICE_TEXT
    assert "root.folders = root.folders.map(" in SERVICE_TEXT
    assert "unread: Math.max(0, (f.unread || 0) - 1)" in SERVICE_TEXT
    assert 'run("markread", [uid, root.folder], false)' in SERVICE_TEXT
    # the bridge call is still made, so the server learns about the read too
    assert '"markread"' in SERVICE_TEXT


def test_compose_warns_before_sending_an_empty_subject():
    """All three competitors ask before sending a subjectless message."""
    assert "property bool subjectWarning: false" in MAIL
    assert "function sendCompose() {" in MAIL
    assert (
        'if (subBox.text.trim() === "") { win.subjectWarning = true; return; }' in MAIL
    )
    assert "function forceSend()" in MAIL
    assert 'text: win.subjectWarning ? Tr.t("Send anyway") : Tr.t("Send")' in MAIL
    assert "onClicked: win.subjectWarning ? win.forceSend() : win.sendCompose()" in MAIL
    assert "No subject — press Send again to send anyway" in MAIL
    assert 'enabled: toBox.text.trim() !== ""' in MAIL


def test_compose_drafts_survive_closing_the_window():
    """A half-written message is kept in the singleton and can be resumed."""
    assert "property var draft: null" in SERVICE_TEXT
    assert "function saveDraft(d) { root.draft = d || null;" in SERVICE_TEXT
    assert 'root.note = Tr.t("Draft saved")' in SERVICE_TEXT
    assert "function clearDraft() { root.draft = null }" in SERVICE_TEXT
    assert 'text: Tr.t("Resume draft")' in MAIL
    assert "visible: !!Mail.draft" in MAIL
    assert "function saveDraft() {" in MAIL
    assert "Mail.saveDraft({ to: toBox.text.trim()" in MAIL
    assert "function resumeDraft() {" in MAIL
    assert "const d = Mail.draft || {}" in MAIL
    assert 'text: Tr.t("Save draft")' in MAIL
    assert "if (sent) Mail.clearDraft();" in MAIL
    assert "onClicked: win.closeCompose(false)" in MAIL  # Cancel keeps the draft


def test_quick_filters_unread_and_starred():
    """Evolution's quick-filter bar: unread and starred toggle chips."""
    assert "property bool filterUnread: false" in MAIL
    assert "property bool filterStarred: false" in MAIL
    assert "function passesFilters(row) {" in MAIL
    assert "if (win.filterUnread && !row.unread) return false;" in MAIL
    assert "if (win.filterStarred && !row.starred) return false;" in MAIL
    assert 'text: Tr.t("Unread")' in MAIL
    assert 'text: Tr.t("Starred")' in MAIL
    assert "Mail.messages.filter(win.passesFilters)" in MAIL


def test_search_operators_refine_the_list_locally():
    """from:, subject: and is:unread|read|starred avoid another IMAP SEARCH."""
    assert "function hasOperators(t)" in MAIL
    assert "function matchesOperators(row, text)" in MAIL
    assert "/\\b(from|subject|is):/i.test(" in MAIL
    assert 'if (key === "from")' in MAIL
    assert 'if (key === "subject")' in MAIL
    assert 'if (val === "unread") return !!row.unread;' in MAIL
    assert 'if (val === "starred") return !!row.starred;' in MAIL
    assert "win.hasOperators(win.filterText) && !win.matchesOperators" in MAIL
    assert "function applySearch(t) {" in MAIL
    assert "if (win.hasOperators(win.filterText)) Mail.query = win.filterText;" in MAIL
    assert "else Mail.search(win.filterText);" in MAIL
    assert "function clearFilters() {" in MAIL
    assert "onAction: win.clearFilters()" in MAIL


def test_multi_select_bulk_actions_and_undo():
    """Thunderbird-style selection with read/star/archive/delete and an undo bar."""
    assert "property var selectedUids: []" in MAIL
    assert "property bool selecting: false" in MAIL
    assert "property var lastBulk: ({})" in MAIL
    assert "function toggleSelect(uid) {" in MAIL
    assert "function selectAll() {" in MAIL
    assert "function bulk(kind) {" in MAIL
    assert "win.lastBulk = { kind: kind, uids: uids };" in MAIL
    # the star flag is the same IMAP flag the single-message button uses
    assert 'Mail.flag(uid, "\\\\Flagged", true)' in MAIL
    assert 'Mail.flag(uid, "\\\\Flagged", false)' in MAIL
    assert 'else if (kind === "archive") Mail.archive(uid);' in MAIL
    assert 'else if (kind === "delete") Mail.remove(uid);' in MAIL
    assert "function undoBulk() {" in MAIL
    assert "function undoAvailable() {" in MAIL
    assert '["read", "star", "unstar"].indexOf(' in MAIL
    assert 'text: Tr.t("Undo");' in MAIL
    assert 'Tr.t("Archived or deleted — no undo")' in MAIL
    assert "if (win.selecting) win.toggleSelect(modelData.uid);" in MAIL


def test_keyboard_navigation_and_shortcuts():
    """j/k move, Enter opens, r/a/s/u act, n finds unread, / searches, Esc backs out."""
    assert "Keys.onPressed: e => { if (win.mailKey(e)) e.accepted = true; }" in MAIL
    assert "function mailKey(e) {" in MAIL
    assert "function isTyping() {" in MAIL
    assert "f instanceof TextInput || f instanceof TextEdit" in MAIL
    if_assert = "if (win.isTyping()) return false;"
    assert if_assert in MAIL
    for key in (
        "Qt.Key_Escape",
        "Qt.Key_Slash",
        "Qt.Key_J",
        "Qt.Key_K",
        "Qt.Key_Return",
        "Qt.Key_C",
        "Qt.Key_R",
        "Qt.Key_A",
        "Qt.Key_S",
        "Qt.Key_U",
        "Qt.Key_N",
    ):
        assert key in MAIL, key
    assert "function moveCursor(delta) {" in MAIL
    assert "function openCursor() {" in MAIL
    assert "function nextUnread(dir) {" in MAIL
    assert "function reply() {" in MAIL
    assert "function forward() {" in MAIL
    assert "searchField.input.forceActiveFocus()" in MAIL


def test_accessibility_names_on_the_new_controls():
    """Screen readers must hear unread state and thread size, not just the subject."""
    assert "Accessible.name: modelData.name + (modelData.unread > 0" in MAIL
    assert 'Accessible.name: (modelData.unread ? Tr.t("Unread") + ", " : "")' in MAIL
    assert 'Tr.t("Conversation, %1 messages", modelData.count)' in MAIL
    assert 'label: Tr.t("Search mail")' in MAIL
    assert 'label: Tr.t("Recipient")' in MAIL
    assert "Accessible.role: Accessible.StaticText" in MAIL
    assert 'Accessible.name: Tr.t("Subject") + ": " + text' in MAIL


def test_offline_error_and_empty_states():
    """A failed server call is distinct from an empty folder or a missing account."""
    assert "property bool error: false" in SERVICE_TEXT
    assert "if (code !== 0) { root.error = true;" in SERVICE_TEXT
    assert "root.error = false;" in SERVICE_TEXT
    assert "if (data && data.error) { root.error = true;" in SERVICE_TEXT
    assert "visible: Mail.error" in MAIL
    assert "Offline or mail server unavailable — check your connection" in MAIL
    assert 'text: Tr.t("Retry")' in MAIL
    assert 'visible: Mail.note !== "" && !Mail.error' in MAIL
    assert "EmptyState {" in MAIL
    assert 'Tr.t("No mail account set up")' in MAIL
    assert 'Tr.t("Loading mail…")' in MAIL
    assert "visible: !Mail.busy && win.visibleMessages().length === 0" in MAIL


def test_message_rows_show_a_body_preview():
    """The bridge already sends a snippet; Thunderbird/Evolution show it in the list."""
    assert 'modelData.snippet ? "\\n" + modelData.snippet : ""' in MAIL
    assert "Mail.when(modelData.date) + (modelData.from ?" in MAIL
    assert 'trailing: modelData.starred ? "★" : ""' in MAIL


def test_clearing_search_no_longer_searches_for_the_folder_name():
    """Passing an empty query as an argv slot resets the list instead of breaking it."""
    assert (
        'function search(q) { root.query = q; run("search", [q || "", root.folder]) }'
        in SERVICE_TEXT
    )
    assert (
        'else { root.openUid = ""; root.subject = ""; root.from = ""; root.body = ""; }'
        in SERVICE_TEXT
    )


def test_existing_mail_actions_are_preserved():
    """The upgrade extends the window; it does not drop the already-tested actions."""
    assert "function markAllRead()" in MAIL
    assert (
        "Mail.messages.forEach(m => { if (m.unread) Mail.markRead(m.uid); });" in MAIL
    )
    assert "onClicked: win.markAllRead()" in MAIL
    assert "ccBox" in MAIL and "bccBox" in MAIL
    assert "Save attachment" in MAIL and "View source" in MAIL
    assert "Load images" in MAIL and "Archive" in MAIL
    assert "Mail.viewSource(Mail.openUid)" in MAIL
    assert "Mail.remove(Mail.openUid)" in MAIL
    for cmd in ("markunread", "flag", "move", "source", "saveattachment", "setremote"):
        assert '"%s"' % cmd in SERVICE_TEXT
