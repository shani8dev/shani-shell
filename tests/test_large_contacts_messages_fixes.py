"""The large Contacts + Messages ("people & messaging") upgrade.

No QML runtime exists in this container, so the shipped bindings and branches
are pinned as static assertions, exactly as the other app-window suites do.
The one behaviour that can be driven here is the vCard bridge: the merge fix
now sends fields the old merge dropped, so a real add/edit/list round trip
proves those fields survive on disk.

Competitors read for this pass: GNOME Contacts (smart lists, link/unlink),
Evolution (conversation search, delivery state, mark/read), Apple Contacts and
Messages (quick compose, per-thread drafts, keyboard navigation) and WhatsApp
Desktop (unread state, conversation actions, notification reply).
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CW = ROOT / "shani/Modules/Contacts/ContactsWindow.qml"
CS = ROOT / "shani/Services/Contacts.qml"
MW = ROOT / "shani/Modules/Messages/MessagesWindow.qml"
LS = ROOT / "shani/Services/Link.qml"
BRIDGE = ROOT / "bridge/contacts.py"


def read(path):
    return path.read_text(encoding="utf-8")


def block(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


def bridge(args, tmp_path):
    env = {
        **os.environ,
        "SHANI_CONTACTS_DIR": str(tmp_path),
        "XDG_DATA_HOME": str(tmp_path),
    }
    return subprocess.run(
        [sys.executable, str(BRIDGE)] + args,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )


# ---- 1. smart lists and live group counts ----------------------------------


def test_smart_lists_are_service_computed_not_saved_groups():
    s, w = read(CS), read(CW)
    assert (
        'readonly property var smartListNames: [Tr.t("Favourites"), Tr.t("No phone"), Tr.t("No email")]'
        in s
    )
    assert (
        "function isSmartList(name) { return smartListNames.indexOf(name) >= 0; }" in s
    )
    assert "function contactsInList(name) {" in s
    assert 'if (name === Tr.t("No phone"))' in s
    assert '!(c.phones || []).some(p => String(p.number || "").trim() !== "")' in s
    assert '!(c.emails || []).some(e => String(e.address || "").trim() !== "")' in s
    assert "function countInList(name) { return contactsInList(name).length; }" in s
    assert "function groupCount(group)" in s
    # the window shows all four chips with a live count and delegates smart lists
    assert (
        'model: [Tr.t("All"), Tr.t("Favourites"), Tr.t("No phone"), Tr.t("No email")].concat(Contacts.allGroups.slice(1))'
        in w
    )
    assert 'text: modelData + "  " + Contacts.countInList(modelData)' in w
    assert (
        "if (Contacts.isSmartList(win.groupFilter)) return Contacts.contactsInList(win.groupFilter);"
        in w
    )


# ---- 2. import / export feedback -------------------------------------------


def test_import_and_export_report_success_and_failure():
    s, w = read(CS), read(CW)
    assert 'property string notice: ""' in s
    assert (
        'function say(message) { root.notice = message || ""; if (root.notice) noticeTimer.restart(); }'
        in s
    )
    assert 'property string _lastAction: ""' in s
    assert "stdout: StdioCollector { id: writeOut }" in s
    assert 'root._lastAction === "import"' in s
    assert 'Tr.t("Imported %1 contact%2", count, count === 1 ? "" : "s")' in s
    assert 'onSaved: root.say(Tr.t("Contacts exported"))' in s
    assert 'root.error = Tr.t("There are no contacts to export");' in s
    assert 'root.error = Tr.t("No file was chosen");' in s
    # both lines are announced, not just painted
    assert w.count("Accessible.role: Accessible.StatusBar") >= 2
    assert "Accessible.name: Contacts.notice" in w
    assert "Accessible.name: Contacts.error" in w


# ---- 3. duplicate merge is data-safe ---------------------------------------


def test_merge_unions_every_field_and_never_folds_my_own_card():
    s = read(CS)
    body = block(s, "function merge(uidA, uidB)", "function undoMerge()")
    for needle in (
        "if (!uidA || !uidB || uidA === uidB) return;",
        "if (!a || !b || a.self || b.self) return;",
        "if (groups.indexOf(g) < 0) groups.push(g);",
        'given: a.given || b.given || ""',
        'family: a.family || b.family || ""',
        "favorite: !!a.favorite || !!b.favorite",
        'avatar: a.avatar || b.avatar || ""',
        "root.lastMerge = { keeper: JSON.parse(JSON.stringify(a)), removed: JSON.parse(JSON.stringify(b)) };",
    ):
        assert needle in body, needle
    # a self card is not even offered as a duplicate
    assert "if (c.self) continue;" in s


def test_bridge_keeps_every_field_the_new_merge_writes(tmp_path):
    uid = json.loads(bridge(["add", json.dumps({"name": "Ada"})], tmp_path).stdout)[
        "uid"
    ]
    payload = {
        "uid": uid,
        "name": "Ada Lovelace",
        "given": "Ada",
        "family": "Lovelace",
        "phones": [
            {"type": "cell", "number": "+1 555 0100"},
            {"type": "work", "number": "+1 555 0101"},
        ],
        "emails": [{"type": "home", "address": "ada@example.test"}],
        "groups": ["friends", "work"],
        "favorite": True,
        "avatar": "/tmp/ada.png",
    }
    assert json.loads(bridge(["edit", json.dumps(payload)], tmp_path).stdout)["ok"]
    row = json.loads(bridge(["list"], tmp_path).stdout)[0]
    assert row["given"] == "Ada" and row["family"] == "Lovelace"
    assert [p["number"] for p in row["phones"]] == ["+1 555 0100", "+1 555 0101"]
    assert row["groups"] == ["friends", "work"]
    assert row["favorite"] is True and row["avatar"] == "/tmp/ada.png"


# ---- 4. unlink / undo a merge ----------------------------------------------


def test_undo_merge_restores_both_cards_and_is_offered_in_the_window():
    s, w = read(CS), read(CW)
    body = block(s, "function undoMerge()", "Process {")
    assert "root.lastMerge" in body and "root.lastMerge = null;" in body
    assert 'root.run(["edit", JSON.stringify(k)]);' in body
    assert 'root.run(["add", JSON.stringify({ name: r.name' in body
    assert "phones: r.phones || [], emails: r.emails || []" in body
    assert 'text: Tr.t("Undo last merge")' in w
    assert "enabled: !!Contacts.lastMerge" in w
    assert "onClicked: Contacts.undoMerge()" in w


# ---- 5. quick compose from a contact ---------------------------------------


def test_contact_hands_its_number_to_the_messages_app():
    w = read(CW)
    fn = block(w, "function messageContact(c)", "Connections {")
    assert "const numbers = (c.phones || [])" in fn
    assert "Ui.messagesNumber = numbers[0];" in fn
    assert "Ui.messages = true;" in fn
    assert 'Contacts.say(Tr.t("This contact has no phone number"))' in fn
    assert 'text: Tr.t("Message…")' in w
    assert "onClicked: win.messageContact(detailCol.c)" in w
    assert "onClicked: win.messageContact(modelData)" in w
    # the row-wide click catcher has z:1; the action row must sit above it
    assert (
        "z: 2                 // the icon actions must win over the row's z:1 click catcher"
        in w
    )


# ---- 6. keyboard navigation in Contacts ------------------------------------


def test_contacts_keyboard_shortcuts_and_wrapping_selection():
    w = read(CW)
    assert "property int currentIndex: -1" in w
    assert "currentIndex: win.currentIndex" in w
    assert "function step(delta)" in w
    assert "(i + delta + rows.length) % rows.length" in w
    assert "list.positionViewAtIndex(win.currentIndex, ListView.Contain)" in w
    assert "function newContact() {" in w
    assert "onGroupFilterChanged: win.currentIndex = -1" in w
    assert "function onQueryChanged() { win.currentIndex = -1; }" in w
    keys = block(w, "Keys.onPressed: e => {", "ColumnLayout {")
    assert "(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F" in keys
    assert "searchField.forceActiveFocus();" in keys
    assert "win.newContact(); e.accepted = true;" in keys
    assert "win.step(e.key === Qt.Key_Down ? 1 : -1); e.accepted = true;" in keys
    assert "win.showContact(rows[win.currentIndex]);" in keys


# ---- 7. conversation search -------------------------------------------------


def test_conversation_search_covers_name_number_and_last_line():
    s, w = read(LS), read(MW)
    body = block(s, "function visibleConversations(query)", "function send(text)")
    assert "if (!needle) return root.messages;" in body
    assert "return root.messages.filter(m => [m.name, m.number, m.text]" in body
    assert '.some(v => String(v || "").toLowerCase().indexOf(needle) >= 0));' in body
    assert 'objectName: "messageSearch"' in w
    assert "onTextChanged: win.search = text" in w
    assert "model: Link.visibleConversations(win.search)" in w
    assert 'Tr.t("Nothing matches %1", win.search)' in w
    assert 'actionText: win.search !== "" ? Tr.t("Clear search") : ""' in w
    assert 'onAction: { searchBox.text = ""; win.search = ""; }' in w


# ---- 8. notification / reply handoff ---------------------------------------


def test_notification_reply_matches_a_normalized_number_and_focuses_the_composer():
    s, w = read(LS), read(MW)
    assert (
        'function digitsOf(value) { return String(value || "").replace(/\\D/g, ""); }'
        in s
    )
    assert "function matchesParty(m, want) {" in s
    assert "const d = digitsOf(w);" in s
    assert "return d.length >= 5 && d === digitsOf(m.number);" in s
    assert "Link.messages.find(m => Link.matchesParty(m, want))" in w
    assert "Qt.callLater(() => reply.forceActiveFocus());" in w


# ---- 9. draft persistence across restarts ----------------------------------


def test_drafts_are_written_to_state_and_restored_on_startup():
    s, w = read(LS), read(MW)
    assert (
        'readonly property string draftsPath: Quickshell.statePath("message-drafts.json")'
        in s
    )
    assert "id: draftStore" in s and "printErrors: false" in s
    assert "try { data = JSON.parse(text()); } catch (e) {}" in s
    assert 'typeof data === "object" && !Array.isArray(data) ? data : ({});' in s
    assert "onLoadFailed: root.drafts = ({})" in s
    assert "onTriggered: draftStore.setText(JSON.stringify(root.drafts))" in s
    assert "function saveDrafts() { draftTimer.restart(); }" in s
    assert "function setDraft(text) {" in s
    assert "root.drafts[root.openThread] = text;" in s
    assert "root.saveDrafts();" in s
    assert 'if (root.openThread !== id) root.sendState = "";' in s
    assert "delete root.drafts[root.openThread]" in s
    assert "onTextChanged: { if (Link.draft !== text) Link.setDraft(text); }" in w
    assert "text: Link.draft" in w


# ---- 10. delivery status ----------------------------------------------------


def test_send_state_reports_sending_sent_and_error_without_inventing_receipts():
    s, w = read(LS), read(MW)
    assert 'property string sendState: ""' in s
    assert "property var lastSend: null" in s
    send = block(s, "function send(text)", "function dial(number)")
    assert 'if (t === "" || root.openThread === "") return;' in send
    assert 'root.sendState = "sending";' in send
    assert "root.lastSend = { thread: root.openThread, text: t };" in send
    sent = block(s, '} else if (what === "send") {', '} else if (what === "dial")')
    assert 'root.sendState = data && data.error ? "error" : "sent";' in sent
    assert "not exposed by MAP or KDE Connect" in sent
    assert 'Tr.t("Sending…")' in w and 'Tr.t("Sent")' in w
    assert 'Tr.t("Not sent — tap Send to retry")' in w


# ---- 11. conversation actions ----------------------------------------------


def test_conversation_rows_offer_call_and_copy_number():
    s, w = read(LS), read(MW)
    assert "import Quickshell" in w
    assert "Quickshell.clipboardText = s;" in w
    delegate = block(w, "delegate: ListRow {", "EmptyState {")
    assert 'onClicked: Link.dial(modelData.number || "")' in delegate
    assert "onClicked: win.copyText(modelData.number)" in delegate
    assert 'accessibleName: Tr.t("Call %1"' in delegate
    assert 'accessibleName: Tr.t("Copy number of %1"' in delegate
    assert 'trailing: modelData.unread ? Tr.t("Unread") : ""' in delegate
    dial = block(s, "function dial(number)", "function hangup()")
    assert 'if (!n) { root.note = Tr.t("No number to call"); return; }' in dial


# ---- 12. empty / error states, a11y and Messages keyboard -------------------


def test_messages_empty_states_are_loading_no_phone_search_and_empty():
    w = read(MW)
    empty = block(w, "EmptyState {", "\n    }\n\n    // ---- one conversation")
    assert "visible: list.count === 0" in empty
    assert 'Tr.t("Loading conversations…")' in empty
    assert 'Tr.t("No phone is connected")' in empty
    assert 'Tr.t("No conversations")' in empty
    assert 'Tr.t("Pair a phone in Settings › Phone")' in empty
    thread = block(
        w, "EmptyState {\n                anchors.centerIn: parent", "}\n        }"
    )
    assert 'title: Tr.t("Nothing said yet")' in thread
    assert 'subtitle: Tr.t("Write the first message below")' in thread


def test_messages_keyboard_and_accessibility_names():
    w = read(MW)
    keys = block(w, "Keys.onEscapePressed: {", "// ---- the conversations")
    assert 'if (win.search !== "") { searchBox.text = ""; win.search = ""; }' in keys
    assert 'Link.openDevice(Link.phone ? Link.phone.id : "");' in keys
    assert "else Ui.messages = false;" in keys
    assert "(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F" in keys
    assert "searchBox.forceActiveFocus();" in keys
    assert w.count("Accessible.role: Accessible.List") == 2
    assert 'Accessible.name: Tr.t("Conversations")' in w
    assert 'Accessible.name: Tr.t("Conversation")' in w
    assert 'label: Tr.t("Message to %1")' in w
    assert w.count("Accessible.role: Accessible.StatusBar") >= 3


# ---- earlier contracts still hold ------------------------------------------


def test_earlier_contacts_and_messages_contracts_still_hold():
    cw, cs, mw, ls = read(CW), read(CS), read(MW), read(LS)
    assert "Contacts.favoriteContacts" in cw
    assert "Contacts.listContactsInGroup(win.groupFilter)" in cw
    assert "Contacts.exportAll(paths[0])" in cw
    assert "paths.forEach(p => Contacts.importFile(p))" in cw
    assert "Accessible.onPressAction: win.showContact(modelData)" in cw
    assert "Accessible.onPressAction: root.clicked()" not in cw  # no local Button copy
    assert "phones: c.phones || []" in cs and "emails: c.emails || []" in cs
    assert "function startConversation(number)" in ls
    assert "else Link.startConversation(want);" in mw
    assert "root.drafts[root.openThread] = root.draft" in ls
    assert 'root.draft = root.drafts[id] || ""' in ls
    assert "Link.send(t);" in mw and "Link.clearDraft();" in mw
    assert (
        "onCountChanged: if (count > 0) Qt.callLater(() => thread.positionViewAtEnd())"
        in mw
    )
