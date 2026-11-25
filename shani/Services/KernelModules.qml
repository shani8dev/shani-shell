pragma Singleton
// Loaded kernel modules, read-only from /proc/modules. bridge/modules.py.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_MODULES_TOOL"), "modules.py")
    property var modules: []
    property int count: 0
    property bool loaded: false

    function refresh() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        command: ["python3", root.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                root.modules = Array.isArray(d.modules) ? d.modules : [];
                root.count = d.count || root.modules.length;
                root.loaded = true;
            }
        }
    }
    Component.onCompleted: refresh()
}
