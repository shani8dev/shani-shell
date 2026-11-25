pragma Singleton
// The keys in ~/.ssh/authorized_keys: list, add, remove. bridge/sshkeys.py does
// the file work as the person (no root); this only shows it.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_SSHKEYS_TOOL") || "/usr/lib/shani-shell/sshkeys.py"

    property var keys: []
    property string note: ""
    property bool editable: true
    property string path: ""
    property bool busy: false
    property string error: ""

    function refresh() { if (!listProc.running) listProc.running = true; }

    Process {
        id: listProc
        command: ["python3", root.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                root.keys = Array.isArray(d.keys) ? d.keys : [];
                root.note = d.note || "";
                root.editable = d.editable !== false;
                root.path = d.path || "";
            }
        }
        stderr: StdioCollector {}
        onExited: code => { root.error = code !== 0 ? Tr.t("Could not read the keys") : ""; }
    }

    function add(key) {
        root.error = "";
        root.busy = true;
        addProc.command = ["python3", root.tool, "add", "--key", key];
        addProc.running = true;
    }
    Process {
        id: addProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                if (d.ok) root.refresh(); else root.error = d.error || Tr.t("Could not add that key.");
            }
        }
        onExited: code => { if (code !== 0 && root.busy) { root.busy = false; root.error = Tr.t("Could not add that key."); } }
    }

    function remove(index) {
        root.error = "";
        root.busy = true;
        rmProc.command = ["python3", root.tool, "remove", "--index", String(index)];
        rmProc.running = true;
    }
    Process {
        id: rmProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                if (d.ok) root.refresh(); else root.error = d.error || Tr.t("Could not remove that key.");
            }
        }
        onExited: code => { if (code !== 0 && root.busy) { root.busy = false; root.error = Tr.t("Could not remove that key."); } }
    }

    Component.onCompleted: refresh()
}
