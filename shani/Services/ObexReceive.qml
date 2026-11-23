pragma Singleton
// Files sent to this computer over Bluetooth: bridge/obex-agent.py is obexd's
// agent; each push is a notification with Accept / Decline, each file that
// arrives one with Open / Show in folder. Runs while there is Bluetooth.
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string defaultTool: "/usr/lib/shani-shell/obex-agent.py"
    readonly property string tool: Quickshell.env("SHANI_OBEX_AGENT") || defaultTool
    // shortcut: only "~/..." expands; ".." / control characters are refused so
    // a bad setting cannot point the agent outside the home directory.
    function cleanDir(d) {
        if (typeof d !== "string" || !d) return ""
        const home = Quickshell.env("HOME") || ""
        if (/[\x00-\x1f]/.test(d) || /(^|\/)\.\.(\/|$)/.test(d)) return ""
        return d.replace(/^~(?=\/)/, home)
    }
    readonly property string dir: root.cleanDir(Quickshell.env("SHANI_OBEX_DIR") || Settings.data.obexDir || "")
    property int received: 0
    property string last: ""
    property int agentGen: 0

    function size(n) { return n > 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB"; }

    // The agent (or an env-overridden stand-in) is not trusted with paths.
    function safeName(n) {
        if (typeof n !== "string" || !n) return "received"
        if (/[\x00-\x1f\/\\]/.test(n) || n === "." || n === "..") return "received"
        return n
    }
    function inStore(p) {
        if (typeof p !== "string" || !p) return false
        if (/[\x00-\x1f]/.test(p) || /(^|\/)\.\.(\/|$)/.test(p)) return false
        const base = (root.dir || (Quickshell.env("HOME") || "") + "/Downloads").replace(/\/+$/, "")
        if (!base) return false
        return p === base || p.indexOf(base + "/") === 0
    }
    function fileUrl(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/") }

    Process {
        id: agent
        running: Bluetooth.defaultAdapter !== null || root.tool !== root.defaultTool
        command: ["python3", root.tool].concat(root.dir ? [root.dir] : [])
        stdinEnabled: true
        onRunningChanged: { if (running) root.agentGen++ }
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.ask === "push")
                    askComp.createObject(root, { msg: m, gen: root.agentGen })
                else if (m.received) {
                    if (!root.inStore(m.received)) return
                    root.received++;
                    root.last = m.received;
                    doneComp.createObject(root, { path: m.received });
                } else if (m.failed)
                    Quickshell.execDetached(["notify-send", "-a", "Bluetooth", "-i", "bluetooth-active", "File not received", root.safeName(m.failed)]);
            }
        }
    }
    // a new folder applies at once: the agent relaunches with the new dir
    onDirChanged: {
        if (agent.running)
            agent.running = false
        relaunchTimer.start()
    }
    Timer { id: relaunchTimer; interval: 300; onTriggered: agent.running = true }
    // A notification from a previous agent must never approve a new transfer:
    // request ids restart at 1 on every relaunch.
    function answer(id, ok, gen) {
        if (gen !== undefined && gen !== root.agentGen) return
        if (!agent.running) return
        agent.write(JSON.stringify({ id: id, ok: ok }) + "\n");
    }

    // one notification per push, its button the answer; dismissed = declined
    Component {
        id: askComp
        Process {
            id: ask
            property var msg
            property int gen: 0
            running: true
            // -A implies --wait; -t closes the notification (and this process)
            // after a minute so an ignored push cannot hang obexd forever.
            command: ["notify-send", "-a", "Bluetooth", "-i", "bluetooth-active", "-u", "critical", "-t", "60000", "-A", "accept=Accept", "-A", "decline=Decline",
                      ask.msg.device + " is sending a file", root.safeName(ask.msg.file) + " · " + root.size(ask.msg.size || 0)]
            stdout: StdioCollector { onStreamFinished: { root.answer(ask.msg.id, text.trim() === "accept", ask.gen); ask.destroy(); } }
        }
    }
    Component {
        id: doneComp
        Process {
            id: done
            property string path
            running: true
            command: ["notify-send", "-a", "Bluetooth", "-i", "document-save", "-A", "open=Open", "-A", "folder=Show in folder", "File received", root.safeName(done.path.split("/").pop())]
            stdout: StdioCollector {
                onStreamFinished: {
                    const a = text.trim();
                    if (!root.inStore(done.path)) { done.destroy(); return }
                    if (a === "open")
                        Qt.openUrlExternally(root.fileUrl(done.path));
                    else if (a === "folder")
                        Qt.openUrlExternally(root.fileUrl(done.path.slice(0, done.path.lastIndexOf("/"))));
                    done.destroy();
                }
            }
        }
    }
}
