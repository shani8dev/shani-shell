pragma Singleton
// The focused app's own menus (File, Edit, View ...) in the window menu: read over
// AT-SPI by bridge/appmenu.py when the window menu opens - niri has no app-menu
// protocol, and GTK 4 exports no menu over D-Bus, but the accessibility tree a
// screen reader walks has the menu bar. GTK 3, Qt and XWayland apps show theirs;
// an app that shows none (GTK 4's popover bar, Firefox, Electron) gets its
// desktop actions instead (WindowMenu). Read on open, never cached.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_APPMENU_TOOL") || "/usr/lib/shani-shell/appmenu.py"
    property int pid: 0
    property string title: ""
    property var menus: []              // [{ label, path, enabled, checked, shortcut, items: [...] }]
    property bool loading: false
    property string why: ""             // why there are none (the tests read it)
    property string did: ""             // the last item pressed (the tests read it)
    property int seq: 0

    function load(window) {
        menus = [];
        why = "";
        pid = window && window.pid ? window.pid : 0;
        title = window ? (window.title || "") : "";
        if (!pid) { why = "no process id for this window"; return; }
        loading = true;
        seq++;
        reader.command = ["timeout", "6", "python3", tool, "menu", String(pid), title];
        reader.running = true;
    }
    function activate(path) {
        if (!pid || !path) return;
        presser.command = ["timeout", "6", "python3", tool, "activate", String(pid), path, title];
        presser.running = true;
    }
    function clear() { menus = []; pid = 0; why = ""; }

    Process {
        id: reader
        property int forSeq: 0
        onRunningChanged: if (running) forSeq = root.seq
        stdout: StdioCollector {
            onStreamFinished: {
                if (reader.forSeq !== root.seq) return;     // a newer window menu asked since
                try {
                    const r = JSON.parse(text);
                    root.menus = r.menus || [];
                    root.why = r.why || "";
                } catch (e) { root.menus = []; root.why = "the menu could not be read"; }
                root.loading = false;
            }
        }
        onExited: root.loading = false
    }
    Process {
        id: presser
        stdout: StdioCollector {
            onStreamFinished: { try { const r = JSON.parse(text); root.did = r.done ? r.label : ""; } catch (e) {} }
        }
    }
}
