pragma Singleton
// Which drawing tablet is plugged in, from libwacom's own database lookup
// (libwacom-list-local-devices). The settings already cover what niri 26.04 can
// do — the output it draws on, left-handed, a calibration matrix — so this only
// answers "which one is this", which is what a person with two tablets asks.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_TABLET_LIST_TOOL") || "libwacom-list-local-devices"

    property var devices: []        // the connected tablets, as libwacom names them
    property bool available: true    // the tool is there
    property string error: ""

    function refresh() {
        list.running = false;
        list.running = true;
    }

    Process {
        id: list
        command: ["sh", "-c", 'command -v "$1" >/dev/null 2>&1 || exit 3; "$1" 2>/dev/null', "sh", root.tool]
        stdout: StdioCollector {
            onStreamFinished: {
                root.devices = text.split("\n").map(l => l.trim()).filter(l => l !== "");
            }
        }
        onExited: code => {
            if (code === 3) { root.available = false; root.devices = []; }
        }
    }

    Component.onCompleted: refresh()
}
