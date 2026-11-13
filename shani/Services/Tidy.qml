pragma Singleton
// Tidy and name (Files): a folder - Downloads above all - sorted into folders by
// what each file is, shown first and undone in one click (bridge/tidy.py keeps a
// journal); and a name for a file from its own words, written by Chronoa
// (Agent.Write), offered in Files' rename box to accept or change.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_TIDY_TOOL") || "/usr/lib/shani-shell/tidy.py"

    // ---- sorting -------------------------------------------------------------
    property string folder: ""
    property var planned: []            // [{ from, to, group }]
    property bool planning: false
    property int moved: -1              // the last apply (-1: none yet)
    property bool canUndo: false
    property string note: ""
    readonly property var groups: {
        const g = {};
        for (const m of planned) g[m.group] = (g[m.group] || 0) + 1;
        return Object.keys(g).map(k => ({ group: k, count: g[k] }));
    }

    function plan(dir) {
        folder = dir;
        planned = [];
        moved = -1;
        note = "";
        planning = true;
        planner.command = ["python3", tool, "plan", dir];
        planner.running = true;
    }
    function cancel() { planned = []; folder = ""; }
    function apply() {
        if (!folder || !planned.length) return;
        applier.command = ["python3", tool, "apply", folder];
        applier.running = true;
    }
    function undo() {
        undoer.running = true;
    }
    Process {
        id: planner
        stdout: StdioCollector { onStreamFinished: { try { root.planned = JSON.parse(text); } catch (e) { root.planned = []; } } }
        onExited: { root.planning = false; if (!root.planned.length) root.note = Tr.t("Nothing to sort here: every file is in its place"); }
    }
    Process {
        id: applier
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.moved = r.moved;
                    root.canUndo = r.moved > 0;
                    root.note = Tr.t("%1 files sorted into folders", r.moved);
                } catch (e) { root.note = Tr.t("The files could not be sorted"); }
                root.planned = [];
            }
        }
    }
    Process {
        id: undoer
        command: ["python3", root.tool, "undo"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.canUndo = (r.left || 0) > 0;
                    root.note = r.left ? Tr.t("%1 put back; %2 stayed, as something new has its old name", r.restored, r.left)
                                       : Tr.t("%1 files put back where they were", r.restored);
                } catch (e) {}
            }
        }
    }

    // ---- naming ----------------------------------------------------------------
    property string namingPath: ""
    property string suggestion: ""       // a name, with the file's own extension
    property string namingError: ""
    property bool naming: false
    property int seq: 0
    function suggestName(path) {
        namingPath = path;
        suggestion = "";
        namingError = "";
        naming = true;
        seq++;
        reader.command = ["python3", tool, "text", path];
        reader.running = true;
    }
    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                const words = text.trim();
                const name = root.namingPath.split("/").pop();
                if (!words) {
                    root.naming = false;
                    root.namingError = Tr.t("There are no words in it to name it by");
                    return;
                }
                Bridge.send({ op: "write", id: "n" + root.seq,
                              instruction: "Suggest a short, descriptive file name for this file: three to six words, in the language "
                                  + "of its text, no extension, no punctuation other than hyphens. Reply with the name only.",
                              text: "Current name: " + name + "\n" + words });
            }
        }
    }
    function fileSafe(s) {
        return String(s).split("\n")[0].replace(/[\/\\:*?"<>|]+/g, " ").replace(/\s+/g, " ").replace(/^[.\s]+|[.\s]+$/g, "").slice(0, 80);
    }
    Connections {
        target: Bridge
        function onMessage(msg) {
            if (msg.type !== "written" || msg.id !== "n" + root.seq)
                return;
            root.naming = false;
            if (msg.error) { root.namingError = msg.error; return; }
            const base = root.fileSafe(msg.text);
            const name = root.namingPath.split("/").pop();
            const dot = name.lastIndexOf(".");
            const ext = dot > 0 ? name.slice(dot) : "";
            if (!base) { root.namingError = Tr.t("Chronoa had no name for it"); return; }
            root.suggestion = base.toLowerCase().endsWith(ext.toLowerCase()) ? base : base + ext;
        }
    }
}
