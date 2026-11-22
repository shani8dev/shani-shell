pragma Singleton
// Mail: bridge/mail.py owns the account, the folders and the messages, over
// IMAP for a real account or MailHog's API for a developer server. The window
// is only a view.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_MAIL_TOOL") || "/usr/lib/shani-shell/mail.py"

    property string kind: ""          // "imap" | "mailhog", from the bridge
    property var account: ({})        // { name, email }
    property var folders: []          // [{ name, unread, total }]
    property string folder: "INBOX"
    property var messages: []         // [{ uid, from, subject, date, snippet, unread }]
    property string openUid: ""       // the message being read
    property string subject: ""
    property string from: ""
    property string body: ""
    property bool busy: false
    property string note: ""

    function state() { run("state", []) }
    function refresh() { run("folders", []) }
    function open(name) { folder = name; run("list", [name]) }
    function read(uid) { if (uid) { openUid = uid; run("read", [uid]) } }
    function markRead(uid) { if (uid) run("markread", [uid], false) }
    function remove(uid) { run("delete", [uid]) }
    function send(to, subject, body) { run("send", [to, subject, body]) }

    // one Process, reused: `what` says which answer this is, and is the
    // subcommand the bridge takes
    function run(what, args, redraw) {
        if (job.running) { root.pending = { what: what, args: args, redraw: redraw !== false }; return; }
        start(what, args, redraw);
    }

    function start(what, args, redraw) {
        job.what = what;
        job.redraw = redraw !== false;
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }

    property var pending: null

    function finished(what, text, code) {
        busy = false;
        if (code !== 0) { root.note = Tr.t("The mail server could not answer"); return; }
        let data = null;
        try { data = JSON.parse(text); } catch (e) { root.note = Tr.t("The mail server sent something unreadable"); return; }
        if (what === "state") {
            root.kind = (data && data.kind) || "";
            root.account = (data && data.account) || ({});
        } else if (what === "folders") {
            root.folders = Array.isArray(data) ? data : [];
            if (root.folders.length && !root.folders.some(f => f.name === root.folder))
                root.folder = root.folders[0].name;
            root.open(root.folder);
        } else if (what === "list") {
            root.messages = Array.isArray(data) ? data : [];
            if (root.messages.length) root.read(root.messages[0].uid);
            else { root.openUid = ""; root.subject = ""; root.from = ""; }
        } else if (what === "read") {
            if (data && data.error) { root.note = data.error; return; }
            root.from = (data && data.from) || "";
            root.subject = (data && data.subject) || "";
            root.body = (data && data.text) || "";
            root.markRead(root.openUid);
        } else if (what === "delete") {
            root.refresh();
        }
    }

    Process {
        id: job
        property string what: ""
        property bool redraw: true
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.finished(job.what, out.text, code);
            if (root.pending) {
                const next = root.pending;
                root.pending = null;
                root.start(next.what, next.args, next.redraw);
            }
        }
    }

    Component.onCompleted: { state(); refresh() }
}