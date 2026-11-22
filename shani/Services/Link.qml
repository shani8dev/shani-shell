pragma Singleton
// Link: the phone on this computer — the paired devices, the call history, the
// address book, and the texts, in a window of the shell's own.
//
// bridge/link.py owns every read and every action: it speaks to shani_link
// itself (GSConnect, KDE Connect, plain Bluetooth, the landline, the modem), so
// the window cannot disagree with the daemon about what a device is called or
// what was said. The window is a view, nothing else.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_LINK_TOOL") || "/usr/lib/shani-shell/link.py"

    property string backend: ""          // kdeconnect | gsconnect | bluetooth | ""
    property bool placesCalls: false     // the phone's link can carry a call
    property var lines: []               // the landline and the modem's own lines
    property var devices: []             // [{ id, name, paired, reachable, battery, charging }]
    property var calls: []               // [{ id, line, number, name, direction, missed, when, seconds }]
    property var contacts: []            // [{ name, numbers, emails }]
    property var messages: []            // [{ thread, name, number, text, when, unread }]
    property var thread: []              // [{ text, when, incoming }]
    property string threadName: ""       // who the open conversation is with
    property string openThread: ""       // its id, for the reply box
    property string note: ""
    property bool busy: false

    // the first paired, reachable device: "the phone" of the tile, the Shelf and
    // the dial pad when nothing is named
    readonly property var phone: devices.find(d => d.paired && d.reachable) || null
    readonly property string phoneName: phone ? phone.name : ""

    function refresh() { run("state", []); run("devices", []); run("calls", []) }
    function openDevice(id) {
        root.openThread = "";
        root.thread = [];
        run("messages", id ? [id] : []);
    }
    function showThread(id, name) {
        root.openThread = id;
        root.threadName = name || "";
        run("thread", id ? [id, root.phone ? root.phone.id : ""] : []);
    }
    function send(text) { run("send", [root.openThread, String(text || "")]) }
    function dial(number) { run("dial", String(number || "").trim()) }
    function hangup() { run("hangup", []) }
    function ring() { run("ring", []) }
    function share(path) { run("share", [root.phone ? root.phone.id : "", String(path || "")]) }

    // "2026-11-22T10:00:00+00:00" (seconds) -> "10:00" today, "21 Nov" otherwise
    function when(secs) {
        if (!secs) return "";
        const d = new Date(secs * 1000);
        if (isNaN(d.getTime())) return "";
        if (d.toDateString() === new Date().toDateString()) return Qt.formatTime(d, Settings.data.use24h ? "HH:mm" : "h:mm AP");
        return Qt.formatDate(d, "d MMM");
    }

    // 95 -> "1:35": how long a call lasted
    function clock(secs) {
        const s = Math.max(0, Math.floor(secs || 0));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // one Process, reused: `what` says which answer this is. A call that arrives
    // while the bridge is still answering is queued, not dropped.
    function run(what, args) {
        if (job.running) { root.pending = root.pending.concat([{ what: what, args: args }]); return; }
        start(what, args);
    }

    function start(what, args) {
        job.what = what;
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }

    property var pending: []

    function finished(what, text, code) {
        busy = false;
        let data = null;
        try { data = JSON.parse(text); } catch (e) { root.note = Tr.t("Link could not answer"); return; }
        if (what === "state") {
            root.backend = (data && data.backend) || "";
            root.placesCalls = !!(data && data.placesCalls);
            root.lines = Array.isArray(data && data.lines) ? data.lines : [];
        } else if (what === "devices") {
            root.devices = Array.isArray(data) ? data : [];
        } else if (what === "calls") {
            root.calls = Array.isArray(data) ? data : [];
        } else if (what === "contacts") {
            root.contacts = Array.isArray(data) ? data : [];
        } else if (what === "messages") {
            root.messages = Array.isArray(data) ? data : [];
            if (root.messages.length) root.showThread(root.messages[0].thread, root.messages[0].name || root.messages[0].number);
        } else if (what === "thread") {
            root.thread = Array.isArray(data) ? data : [];
        } else if (what === "send") {
            root.note = data && data.error ? data.error : Tr.t("Text sent");
            if (!data || !data.error) root.openDevice(root.phone ? root.phone.id : "");
        } else if (what === "dial") {
            root.note = data && data.error ? data.error : Tr.t("Calling…");
        } else if (what === "hangup") {
            root.note = data && data.error ? data.error : "";
        } else if (what === "ring" || what === "share") {
            root.note = data && data.error ? data.error : (what === "ring" ? Tr.t("Ringing the phone") : Tr.t("Sent to the phone"));
        }
    }

    Process {
        id: job
        property string what: ""
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.finished(job.what, out.text, code);
            if (root.pending.length) {
                const next = root.pending[0];
                root.pending = root.pending.slice(1);
                root.start(next.what, next.args);
            }
        }
    }

    Component.onCompleted: refresh()
}