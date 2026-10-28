pragma Singleton
// The Bluetooth pairing agent (bridge/bt-agent.py): Quickshell pairs and
// connects but registers no agent, so a phone or keyboard that shows a code
// could not pair. Its questions arrive here and the pairing dialog answers them.
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string defaultTool: "/usr/lib/shani-shell/bt-agent.py"
    readonly property string tool: Quickshell.env("SHANI_BT_AGENT") || defaultTool
    property var ask: null              // { ask: confirm|authorize|pin|passkey, id, device, passkey? }
    property var show: null             // { show: passkey|pin, device, passkey|pin, entered? }

    function answer(ok, value) {
        if (!ask)
            return;
        agent.write(JSON.stringify({ id: ask.id, ok: ok, value: value || "" }) + "\n");
        ask = null;
    }
    function dismiss() { show = null; }

    Process {
        id: agent
        running: Bluetooth.defaultAdapter !== null || root.tool !== root.defaultTool
        command: ["python3", root.tool]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.ask)
                    root.ask = m;
                else if (m.show)
                    root.show = m;
                else if (m.cancel) {
                    root.ask = null;
                    root.show = null;
                }
            }
        }
    }
    // a code to type on a keyboard goes once the keyboard has paired
    Timer { running: root.show !== null; interval: 60000; onTriggered: root.show = null }
}
