pragma Singleton
// The Bluetooth pairing agent (bridge/bt-agent.py): Quickshell pairs and
// connects but registers no agent, so a phone or keyboard that shows a code
// could not pair. Its questions arrive here and the pairing dialog answers them.
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string defaultTool: "/usr/lib/shani-shell/bt-agent.py"
    readonly property string tool: Quickshell.env("SHANI_BT_AGENT") || defaultTool
    property var ask: null              // { ask: confirm|authorize|pin|passkey, id, device, passkey? }
    property var show: null             // { show: passkey|pin, device, passkey|pin, entered? }
    property string agentError: ""      // why bt-agent.py exited, when it did so unexpectedly

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
        stderr: StdioCollector { id: agentErr }
        onExited: code => {
            root.agentError = agentErr.text.trim();
            // an adapter going away is a normal stop; a crash while it is up is not
            if (code !== 0 && root.agentError !== "" && (Bluetooth.defaultAdapter !== null || root.tool !== root.defaultTool))
                Quickshell.execDetached(["notify-send", "-a", "Bluetooth", "-i", "dialog-error",
                    "Bluetooth pairing unavailable", root.agentError.slice(0, 160)]);
        }
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.ask) {
                    // a stale passkey display would mask the prompt (and its
                    // button would answer the wrong ask) — clear it first
                    root.show = null;
                    if (root.ask)
                        root.answer(false); // don't strand the previous BlueZ request
                    root.ask = m;
                }
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

    // Auto-connect (Settings > Network > Bluetooth): paired audio and input
    // devices reconnect on their own when the adapter comes up or they come back
    // in range — phones are left alone (Phone.qml and DynamicLock handle those).
    readonly property bool autoConnect: Settings.loaded && Settings.data.bluetoothAutoConnect && Bluetooth.defaultAdapter !== null
    onAutoConnectChanged: if (autoConnect) reconnectTimer.restart()
    Timer {
        id: reconnectTimer
        interval: 30000
        onTriggered: root.reconnect()
        repeat: Bluetooth.defaultAdapter !== null && root.autoConnect
    }
    function reconnect() {
        if (!root.autoConnect)
            return;
        for (const d of Bluetooth.devices.values) {
            if (d.paired && !d.connected && !d.pairing && /^(audio|input)/.test(d.icon || "") && d.reachable !== false)
                d.connect();
        }
    }
}
