pragma Singleton
// Parental controls (malcontent): the apps this person's app filter blocks, from
// bridge/appfilter.py, which waits on the system bus and tells again when the
// filter changes. The launcher and the dock leave them out, as GNOME Shell does
// (Flatpak itself refuses to run a blocked Flatpak). Setting the filter is
// GNOME's Parental Controls app (malcontent-control), opened from Settings >
// Users for a standard account.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_APPFILTER_TOOL") || "/usr/lib/shani-shell/appfilter.py"
    property bool available: false
    property var blocked: []              // desktop ids
    property bool canControl: false       // malcontent-control is installed

    function allowed(id) { return !id || blocked.indexOf(id) < 0; }
    function openControls(user) { Quickshell.execDetached(["malcontent-control", "--user", user]); }
    function refresh() { bridge.running = false; Qt.callLater(() => bridge.running = true); }

    Process {
        id: bridge
        running: true
        command: [root.tool, "--watch"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    root.available = !!d.available;
                    root.blocked = d.blocked || [];
                } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v malcontent-control"]
        onExited: code => root.canControl = code === 0
    }
}
