pragma Singleton
// Files sent to this computer over Bluetooth: bridge/obex-agent.py is obexd's
// agent; each push is a notification with Accept / Decline, each file that
// arrives one with Open / Show in folder. Runs while there is Bluetooth.
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string defaultTool: "/usr/lib/shani-shell/obex-agent.py"
    readonly property string tool: Quickshell.env("SHANI_OBEX_AGENT") || defaultTool
    property int received: 0
    property string last: ""

    function size(n) { return n > 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB"; }

    Process {
        id: agent
        running: Bluetooth.defaultAdapter !== null || root.tool !== root.defaultTool
        command: ["python3", root.tool]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.ask === "push")
                    askComp.createObject(root, { msg: m });
                else if (m.received) {
                    root.received++;
                    root.last = m.received;
                    doneComp.createObject(root, { path: m.received });
                } else if (m.failed)
                    Quickshell.execDetached(["notify-send", "-a", "Bluetooth", "-i", "bluetooth-active", "File not received", m.failed]);
            }
        }
    }
    function answer(id, ok) { agent.write(JSON.stringify({ id: id, ok: ok }) + "\n"); }

    // one notification per push, its button the answer; dismissed = declined
    Component {
        id: askComp
        Process {
            id: ask
            property var msg
            running: true
            command: ["notify-send", "-a", "Bluetooth", "-i", "bluetooth-active", "-u", "critical", "-A", "accept=Accept", "-A", "decline=Decline",
                      msg.device + " is sending a file", msg.file + " · " + root.size(msg.size)]
            stdout: StdioCollector { onStreamFinished: { root.answer(ask.msg.id, text.trim() === "accept"); ask.destroy(); } }
        }
    }
    Component {
        id: doneComp
        Process {
            id: done
            property string path
            running: true
            command: ["notify-send", "-a", "Bluetooth", "-i", "document-save", "-A", "open=Open", "-A", "folder=Show in folder", "File received", path.split("/").pop()]
            stdout: StdioCollector {
                onStreamFinished: {
                    const a = text.trim();
                    if (a === "open")
                        Qt.openUrlExternally("file://" + done.path);
                    else if (a === "folder")
                        Qt.openUrlExternally("file://" + done.path.slice(0, done.path.lastIndexOf("/")));
                    done.destroy();
                }
            }
        }
    }
}
