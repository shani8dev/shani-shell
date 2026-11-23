pragma Singleton
// The boot slots: which one this machine is running from, which is current, and
// what a boot left behind. bridge/bootinfo.py reads `shani-deploy --status
// --json` (no root, no deploy lock); the window only shows it. Rollback stays
// with shani-deploy and authorisation, as the page says.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_BOOTINFO_TOOL") || "/usr/lib/shani-shell/bootinfo.py"

    property bool available: false
    property var rows: []
    property string note: ""

    function refresh() { run.running = false; run.running = true; }

    Process {
        id: run
        command: ["python3", root.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                root.available = !!d.available;
                root.rows = Array.isArray(d.rows) ? d.rows : [];
                root.note = d.note || "";
            }
        }
    }

    Component.onCompleted: refresh()
}

