pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_SECURITY_TOOL") || "/usr/lib/shani-shell/security.py"
    property var report: ({})
    property bool loaded: false
    function refresh() { if (!proc.running) proc.running = true; }
    Process {
        id: proc
        command: ["python3", root.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                root.report = d;
                root.loaded = true;
            }
        }
    }
    Component.onCompleted: refresh()
}
