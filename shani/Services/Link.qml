pragma Singleton
// Link: the phone on this computer — the paired devices, the call history, the
// address book, and the texts, in a window of the shell's own.
//
// bridge/link.py owns every read and every action: it speaks to phone
// itself (GSConnect, KDE Connect, plain Bluetooth, the landline, the modem), so
// the window cannot disagree with the daemon about what a device is called or
// what was said. The window is a view, nothing else.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/Time.js" as Time
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_PHONE_TOOL"), "link.py")

    property string backend: ""          // kdeconnect | gsconnect | bluetooth | ""
    property bool placesCalls: false     // the phone's link can carry a call
    property var lines: []               // the landline and the modem's own lines
    property var devices: []             // [{ id, name, paired, reachable, battery, charging }]
    property var calls: []               // [{ id, line, number, name, direction, missed, when, seconds }]
    property var contacts: []            // [{ name, numbers, emails }]
    property var messages: []            // [{ thread, name, number, text, when, unread }]
    property bool messagesLoaded: false  // the latest "messages" answer has arrived
    property var thread: []              // [{ text, when, incoming }]
    property string threadName: ""       // who the open conversation is with
    property string openThread: ""       // its id, for the reply box
    property var drafts: ({})            // unsent text, keyed by thread id
    property string draft: ""            // the open thread's draft, for the composer
    property string note: ""
    property bool busy: false
    property string search: ""           // conversation filter, owned by the Messages window
    property string sendState: ""        // "" | "sending" | "sent" | "error" — the composer's delivery line
    property var lastSend: null          // { thread, text } of the last attempted send

    // the first paired, reachable device: "the phone" of the tile, the Shelf and
    // the dial pad when nothing is named
    readonly property var phone: devices.find(d => d.paired && d.reachable) || null
    readonly property string phoneName: phone ? phone.name : ""

    function refresh() { run("state", []); run("devices", []); run("calls", []) }
    function openDevice(id) {
        if (root.openThread !== "") root.drafts[root.openThread] = root.draft;
        root.openThread = "";
        root.thread = [];
        root.draft = "";
        root.messagesLoaded = false;
        root.saveDrafts();
        run("messages", id ? [id] : []);
    }
    function showThread(id, name) {
        if (root.openThread !== "") root.drafts[root.openThread] = root.draft;
        if (root.openThread !== id) root.sendState = "";   // an old "Sent" belongs to the old thread
        root.openThread = id;
        root.threadName = name || "";
        root.draft = root.drafts[id] || "";
        root.saveDrafts();
        root.messages = root.messages.map(m => m.thread === id ? Object.assign({}, m, { unread: false }) : m);
        if (id && root.messages.some(m => m.thread === id)) run("read", [id]);
        run("thread", id ? [id, root.phone ? root.phone.id : ""] : []);
    }
    // a number with no thread yet: same composer, just addressed to the number
    function startConversation(number) {
        showThread(String(number || ""), String(number || ""));
    }

    // Drafts must outlive the shell: Apple Messages and WhatsApp both keep an
    // unsent line when the app closes. A FileView writes the JSON atomically,
    // never through argv or a shell string.
    readonly property string draftsPath: Quickshell.statePath("message-drafts.json")
    FileView {
        id: draftStore
        path: root.draftsPath
        printErrors: false
        onLoaded: {
            let data = null;
            try { data = JSON.parse(text()); } catch (e) {}
            root.drafts = data && typeof data === "object" && !Array.isArray(data) ? data : ({});
        }
        onLoadFailed: root.drafts = ({})
    }
    Timer { id: draftTimer; interval: 600; onTriggered: draftStore.setText(JSON.stringify(root.drafts)) }
    function saveDrafts() { draftTimer.restart(); }
    function setDraft(text) {
        if (root.openThread !== "") root.drafts[root.openThread] = text;
        root.draft = text;
        root.saveDrafts();
    }
    function clearDraft() {
        if (root.openThread !== "") delete root.drafts[root.openThread];
        root.draft = "";
        root.saveDrafts();
    }

    // A number from a notification may carry spaces, a country code or be the
    // contact's name; all still mean the same thread to the phone.
    function digitsOf(value) { return String(value || "").replace(/\D/g, ""); }
    function matchesParty(m, want) {
        const w = String(want || "").trim();
        if (!w) return false;
        if ((m.name || "") === w || (m.number || "") === w) return true;
        const d = digitsOf(w);
        return d.length >= 5 && d === digitsOf(m.number);
    }
    // search covers the sender, number and the latest snippet; a full body
    // search needs the bridge to send every thread's text, which MAP cannot.
    function visibleConversations(query) {
        const needle = String(query || "").trim().toLowerCase();
        if (!needle) return root.messages;
        return root.messages.filter(m => [m.name, m.number, m.text]
            .some(v => String(v || "").toLowerCase().indexOf(needle) >= 0));
    }

    function send(text) {
        const t = String(text || "").trim();
        if (t === "" || root.openThread === "") return;
        root.lastSend = { thread: root.openThread, text: t };
        root.sendState = "sending";
        run("send", [root.openThread, t]);
    }
    function dial(number) {
        const n = String(number || "").trim();
        if (!n) { root.note = Tr.t("No number to call"); return; }
        run("dial", n);
    }
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
        return Time.clock(Math.max(0, Math.floor(secs || 0)));
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
            root.messagesLoaded = true;
        } else if (what === "thread") {
            root.thread = Array.isArray(data) ? data : [];
        } else if (what === "send") {
            root.note = data && data.error ? data.error : Tr.t("Text sent");
            // The bridge knows only ok/error; real delivered/read receipts are
            // not exposed by MAP or KDE Connect, so do not invent ticks for them.
            root.sendState = data && data.error ? "error" : "sent";
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
