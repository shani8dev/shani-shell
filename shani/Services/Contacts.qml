pragma Singleton
// Contacts: Shani Link's address book (shani-link shani_link/contacts.py —
// vCard files in $XDG_DATA_HOME/shani-link/contacts/, read and written by
// bridge/contacts.py). No Evolution Data Server, no EDS/EBook bindings:
// the folder *is* the export, and Shani Link's lookup reads the same files.
//
// The panel (Modules/Contacts/ContactsPanel.qml) shows the list with live
// search, add/edit/delete, click-to-copy for phone and email, a "Call"
// action and vCard import from a file.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_CONTACTS_TOOL") || "/usr/lib/shani-shell/contacts.py"
    property var contacts: []          // [{uid, name, given, family, phone, email, phones, emails}]
    property string query: ""          // the live-search text (the panel's box)
    property bool loaded: false        // one answer has come back
    property string error: ""          // the last failure, "" when the last write was fine
    property string lastCopied: ""     // the text last copied (for the tests)
    property string lastCalled: ""     // the number last handed to the dial pad

    function refresh() {
        if (readProc.running)
            return;
        readProc.query = root.query;
        readProc.running = true;
    }

    function search(q) {
        query = String(q || "");
        debounce.restart();
    }
    function browse() { search(""); }

    // ---- writes ------------------------------------------------------------------
    // payloads: add {name, phone, email}; edit {uid, name, phone, email};
    // delete {uid}; import {path} (the bridge also reads a bare path)
    function addContact(name, phone, email) { _write("add", { name: String(name || ""), phone: String(phone || ""), email: String(email || "") }); }
    function editContact(uid, name, phone, email) { _write("edit", { uid: String(uid || ""), name: String(name || ""), phone: String(phone || ""), email: String(email || "") }); }
    function deleteContact(uid) { _write("delete", { uid: String(uid || "") }); }
    function importVCard(path) {
        const p = String(path || "");
        if (p === "")
            return;
        _write("import", { path: p });
    }

    function _write(action, payload) {
        error = "";
        writeProc.command = ["python3", root.tool, action, JSON.stringify(payload)];
        if (!writeProc.running)
            writeProc.running = true;
    }

    // ---- copy / call / text --------------------------------------------------------
    function copyText(text) {
        const t = String(text || "");
        if (t === "")
            return;
        Quickshell.clipboardText = t;
        lastCopied = t;
        Quickshell.execDetached(["notify-send", "-a", "Contacts", t]);
    }
    function copyPhone(contact) {
        if (contact && contact.phone)
            copyText(contact.phone);
    }
    function copyEmail(contact) {
        if (contact && contact.email)
            copyText(contact.email);
    }
    // "Call" hands the number to Shani Link's dial pad (the modem's voice
    // line, or a phone over Bluetooth — the same handoff Modem.callNumber
    // does with a tel: URL). Nothing is dialled until Shani Link confirms.
    function callNumber(number) {
        const n = String(number || "");
        if (n === "") {
            error = Tr.t("No phone number to call");
            return;
        }
        error = "";
        lastCalled = n;
        Modem.callNumber(n);
    }
    // "Text" opens this shell's SMS dialog for the number (ModemDialog,
    // the same Ui prefix textMessage uses — see shell.qml textMessage()).
    function textNumber(number) {
        const n = String(number || "");
        if (n === "") {
            error = Tr.t("No phone number to text");
            return;
        }
        error = "";
        Ui.closeAll();
        Ui.smsTo = n;
        Ui.modemDialog = "sms";
    }

    Timer {
        id: debounce
        interval: 200
        onTriggered: {
            readProc.query = root.query;
            readProc.running = true;
        }
    }

    Process {
        id: readProc
        property string query: ""
        command: ["python3", root.tool, "list", query]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "[]");
                    root.contacts = Array.isArray(data) ? data : [];
                    root.error = "";
                } catch (e) {
                    root.contacts = [];
                    root.error = Tr.t("Could not read the contacts");
                }
                root.loaded = true;
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.error = Tr.t("Could not read the contacts");
                root.loaded = true;
            }
        }
    }

    Process {
        id: writeProc
        onExited: code => {
            if (code !== 0)
                root.error = Tr.t("That change was not saved");
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.refresh() }
}
