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
    property string date: ""
    property string body: ""
    property string html: ""          // the same message as it was sent, made safe (bridge)
    property var attachments: []      // [{ name, type, size }] - named, not fetched
    property bool showHtml: false     // render the original formatting instead of the text
    property bool remoteImages: false // opted in to images that reach outside the message
    property string source: ""        // the raw message, for "View source"
    property string query: ""         // what the search box is looking for
    property bool busy: false
    property string note: ""

    // an IMAP date string -> "10:00" today, "21 Nov" otherwise
    function when(value) {
        if (!value) return "";
        const d = new Date(value);
        if (isNaN(d.getTime())) return String(value).slice(0, 16);
        if (d.toDateString() === new Date().toDateString()) return Qt.formatTime(d, "HH:mm");
        return Qt.formatDate(d, "d MMM");
    }

    function state() { run("state", []) }
    function refresh() { run("folders", []) }
    function open(name) { folder = name; run("list", [name]) }
    function read(uid) { if (uid) { openUid = uid; run("read", [uid, root.folder]) } }
    function markRead(uid) { if (uid) run("markread", [uid, root.folder], false) }
    function remove(uid) { if (uid) run("delete", [uid, root.folder]) }
    function markUnread(uid) { if (uid) run("markunread", [uid, root.folder]) }
    function flag(uid, name, on) { if (uid) run("flag", [uid, name, on ? "1" : "0", root.folder]) }
    function archive(uid) { if (uid) run("move", [uid, "Archive", root.folder]) }
    function viewSource(uid) { if (uid) run("source", [uid, root.folder]) }
    function saveAttachment(uid, index, path) { if (uid && path) run("saveattachment", [uid, String(index), path, root.folder]) }
    function setRemoteImages(on) { run("setremote", [on ? "1" : "0"]) }
    // cc and bcc are optional argv slots, never part of a shell string
    function send(to, subject, body, cc, bcc) {
        let args = [to, subject, body];
        if (cc || bcc) args.push(cc || "");
        if (bcc) args.push(bcc);
        run("send", args);
    }
    // a word in the sender, the subject or the body: the server looks (IMAP
    // SEARCH), or the reader does when the server cannot
    function search(q) { root.query = q; run("search", q ? [q, root.folder] : [root.folder]) }

    // 412 -> "412 B", ivar 12345 -> "12.3 kB": the same units the archive and
    // disk usage views use, so an attachment reads like a file
    function size(bytes) {
        const units = ["B", "kB", "MB", "GB"];
        let v = bytes, i = 0;
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        return (i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)) + " " + units[i];
    }

    // one Process, reused: `what` says which answer this is, and is the
    // subcommand the bridge takes
    function run(what, args, redraw) {
        if (job.running) {
            root.pending = root.pending.concat([{ what: what, args: args, redraw: redraw !== false }]);
            return;
        }
        start(what, args, redraw);
    }

    function start(what, args, redraw) {
        root.busy = true;
        job.what = what;
        job.redraw = redraw !== false;
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }

    property var pending: []          // what to run next: a queue, not one slot

    function finished(what, text, code) {
        busy = false;
        if (code !== 0) { root.note = Tr.t("The mail server could not answer"); return; }
        let data = null;
        try { data = JSON.parse(text); } catch (e) { root.note = Tr.t("The mail server sent something unreadable"); return; }
        if (what === "state") {
            root.kind = (data && data.kind) || "";
            root.account = (data && data.account) || ({});
            root.remoteImages = !!(data && data.remoteImages);
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
            root.source = "";
            root.from = (data && data.from) || "";
            root.subject = (data && data.subject) || "";
            root.date = (data && data.date) || "";
            root.body = (data && data.text) || "";
            root.html = (data && data.html) || "";
            root.attachments = Array.isArray(data && data.attachments) ? data.attachments : [];
            root.showHtml = root.html !== "";
            root.markRead(root.openUid);
        } else if (what === "search") {
            root.messages = Array.isArray(data) ? data : [];
            if (root.messages.length) root.read(root.messages[0].uid);
        } else if (what === "delete") {
            root.refresh();
        } else if (what === "markunread" || what === "flag" || what === "move") {
            root.note = what === "move" ? Tr.t("Message moved to Archive") : Tr.t("Message updated");
            root.refresh();
        } else if (what === "source") {
            root.source = (data && data.source) || (data && data.error) || "";
        } else if (what === "saveattachment") {
            root.note = data && data.error ? data.error : Tr.t("Attachment saved");
        } else if (what === "setremote") {
            root.remoteImages = !!(data && data.remote);
            if (root.openUid) root.read(root.openUid);
        } else if (what === "send") {
            root.note = data && data.error ? data.error : Tr.t("Message sent");
        }
    }

    Process {
        id: job
        property string what: ""
        property bool redraw: true
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.finished(job.what, out.text, code);
            if (root.pending.length) {
                const next = root.pending[0];
                root.pending = root.pending.slice(1);
                root.start(next.what, next.args, next.redraw);
            }
        }
    }

    Component.onCompleted: { state(); refresh() }
}
