pragma Singleton
// IRC: bridge/irc.py owns the socket and the wire protocol. This singleton is
// the view of it - the connection form's values, the channels and nicks, the
// timeline, unread/mention badges - and stays alive across window closes so a
// reconnect does not lose the conversation.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_IRC_TOOL"), "irc.py")

    // the connection form
    property string server: "irc.libera.chat"
    property int port: 6697
    property string nick: ""
    property bool tls: true

    property string status: "disconnected"  // disconnected | connecting | connected | error
    property string error: ""               // last failure, including a missing tool
    property string note: ""                // last successful status
    property bool busy: false               // one connect command in flight
    property var channels: []
    property var nicks: ({})                // channel -> [nick]
    property var messages: []               // [{ seq, channel, nick, text, time, mention }]
    property string activeChannel: ""
    property var unread: ({})               // channel -> count
    property var mentions: ({})             // channel -> count
    property int lastSeq: 0
    property bool shown: false              // the window is up: its channel is read
    signal messageArrived(var msg)

    function run(obj) { return root.send(obj); }
    function send(obj) {
        if (!proc.running) return false;
        proc.write(JSON.stringify(obj) + "\n");
        return true;
    }

    function connect() {
        root.error = "";
        root.busy = true;
        if (!root.nick) root.nick = "shani" + Math.floor(Math.random() * 1000);
        root.status = "connecting";
        root.pendingConnect = { op: "connect", server: root.server, port: root.port,
                                nick: root.nick, tls: root.tls };
        proc.running = true;
    }
    property var pendingConnect: null

    function join(channel) {
        const ch = String(channel || "").trim();
        if (!ch) return false;
        if (root.channels.indexOf(ch) < 0) {
            root.channels = root.channels.concat([ch]);
            root.activeChannel = ch;
        }
        return root.send({ op: "join", channel: ch });
    }
    function part(channel) {
        const ch = String(channel || "").trim();
        if (!ch) return false;
        root.channels = root.channels.filter(c => c !== ch);
        if (root.activeChannel === ch) root.activeChannel = root.channels.length ? root.channels[0] : "";
        return root.send({ op: "part", channel: ch });
    }
    function say(channel, text) {
        const msg = String(text || "").trim();
        if (!channel || !msg) return false;
        return root.send({ op: "say", channel: channel, text: msg });
    }
    function quit() {
        root.send({ op: "quit" });
        root.status = "disconnected";
        proc.running = false;
        root.channels = [];
        root.nicks = ({});
        root.activeChannel = "";
    }
    function reconnect() { root.quit(); root.connect(); }

    function markRead(channel) {
        root.activeChannel = channel || "";
        const u = Object.assign({}, root.unread); delete u[channel]; root.unread = u;
        const m = Object.assign({}, root.mentions); delete m[channel]; root.mentions = m;
    }
    function noteMessage(msg) {
        if (!msg) return;
        const old = root.messages;
        if (old.some(m => m.seq === msg.seq)) return;   // event + poll can both bring one
        root.messages = old.concat([msg]).slice(-2000);
        if (msg.seq > root.lastSeq) root.lastSeq = msg.seq;
        if (!root.shown || msg.channel !== root.activeChannel) {
            const u = Object.assign({}, root.unread);
            u[msg.channel] = (u[msg.channel] || 0) + 1;
            root.unread = u;
        }
        if (msg.mention) {
            const mn = Object.assign({}, root.mentions);
            mn[msg.channel] = (mn[msg.channel] || 0) + 1;
            root.mentions = mn;
        }
        root.messageArrived(msg);
    }

    // the stdin daemon's result path: SplitParser -> onLine -> finished
    function finished(line) {
        let msg = null;
        try { msg = JSON.parse(line); } catch (e) { return; }
        if (!msg || !msg.event) return;
        if (msg.event === "status") {
            root.status = msg.status || "disconnected";
            root.error = msg.error || "";
            root.busy = false;
            root.note = root.status === "connected" ? Tr.t("Connected to %1", root.server) : "";
            if (root.status === "disconnected" || root.status === "error") {
                root.channels = [];
                root.nicks = ({});
                root.activeChannel = "";
                proc.running = false;
            }
        } else if (msg.event === "channels") {
            root.channels = msg.channels || [];
            root.nicks = msg.nicks || root.nicks;
            if (root.activeChannel === "" && root.channels.length) root.activeChannel = root.channels[0];
        } else if (msg.event === "nicks") {
            const n = Object.assign({}, root.nicks); n[msg.channel] = msg.nicks || []; root.nicks = n;
        } else if (msg.event === "message") {
            root.noteMessage(msg.message);
        } else if (msg.event === "messages") {
            (msg.messages || []).forEach(root.noteMessage);
        } else if (msg.event === "error") {
            root.error = msg.error || "";
        }
    }
    function onLine(line) { root.finished(line); }

    Process {
        id: proc
        command: ["python3", root.tool]
        stdinEnabled: true
        onStarted: {
            if (root.pendingConnect) {
                proc.write(JSON.stringify(root.pendingConnect) + "\n");
                root.pendingConnect = null;
            }
        }
        stdout: SplitParser { onRead: line => root.onLine(line) }
        onExited: code => {
            root.busy = false;
            if (code === 127) {
                root.error = Tr.t("The IRC service is not installed");
                root.status = "error";
            }
            if (root.status !== "disconnected") {
                root.status = "disconnected";
                root.channels = [];
                root.nicks = ({});
            }
        }
    }
    // a slow reconcile: the bridge also pushes each message, but after a
    // reconnect the window can ask for everything since the last seq it saw
    Timer {
        interval: 2000
        repeat: true
        running: proc.running
        onTriggered: root.send({ op: "messages", since: root.lastSeq })
    }
}
