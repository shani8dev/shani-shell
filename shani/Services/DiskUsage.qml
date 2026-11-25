pragma Singleton
// DiskUsage (disk treemap): what is eating the disk, as rectangles whose
// area is their size. A python3 walk lists a directory's children — sizes
// via os.path.getsize (directories summed by walking them), sorted
// biggest-first, capped at ~200 entries, skipping /proc /sys /dev — and
// DiskUsage.js lays them out as a treemap of weighted rectangles. Click a
// folder to walk into it (Esc / back to go up), click a file to mark it
// for removal, review the marked list, then move it to the trash with
// `gio trash`. Nothing is deleted until that review is confirmed.
// Shown by Modules/DiskUsage/DiskUsagePanel.qml until closed.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "DiskUsage.js" as DiskUsageLogic
import "../Common/Format.js" as Format

Singleton {
    id: root
    property string scanRoot: homeDir()    // the scan root (default home)
    property string current: ""            // the directory on screen
    property var entries: []               // [{ path, name, size, isDir }] biggest-first
    property var marked: []                // paths marked for removal, in scan order
    property var history: []               // parent directories, for back()
    property bool scanning: false
    property string error: ""
    property string last: ""               // result of the last trash, for `state`

    readonly property bool shown: Ui.diskUsage
    readonly property int markedCount: marked.length
    readonly property int totalSize: entries.reduce((s, e) => s + (e.size || 0), 0)
    readonly property var markedPaths: marked   // paths marked for removal

    // ---- capacity: one bounded df per minute, only while the shell is up ------
    // The treemap walks a folder on demand, so there was no size/used/free field
    // for a bar chip to read. df fills one; the poll is lazy and capped at 10 s.
    property var mounts: []                             // [{ target, usedPct }]
    readonly property bool anyFull: mounts.some(m => m.usedPct > 90)
    readonly property int fullestPct: mounts.reduce((mx, m) => Math.max(mx, m.usedPct), 0)

    function pollCapacity() {
        Proc.run("diskusage-df", ["df", "--output=pcent,target"], (out, code) => {
            if (code !== 0) return;
            const rows = String(out || "").split("\n").slice(1);   // drop the "Use% Mounted on" header
            const parsed = [];
            for (const line of rows) {
                const m = /^\s*(\d+)%\s+(.+?)\s*$/.exec(line);
                if (m) parsed.push({ target: m[2], usedPct: Number(m[1]) });
            }
            root.mounts = parsed;
        }, 0, 10000);
    }
    Timer {
        interval: 60000
        repeat: true
        running: Settings.loaded
        triggeredOnStart: true
        onTriggered: root.pollCapacity()
    }

    function homeDir() { return Quickshell.env("HOME") || "/tmp"; }

    function open(dir) {
        Ui.closeAll();
        Ui.diskUsage = true;
        scanRoot = dir || homeDir();
        current = scanRoot;
        history = [];
        marked = [];
        error = "";
        view = "map";
        scan(scanRoot);
    }
    function close() { Ui.diskUsage = false; }
    function toggle() { root.shown ? close() : open(scanRoot || homeDir()); }

    // ---- scan: python walk over one directory -------------------------------
    // os.path.getsize for files; a directory's size is the sum of the
    // getsize of everything under it. Sorted biggest-first, capped at 200
    // entries, /proc /sys /dev skipped wherever they appear.
    readonly property string scanScript: [
        "import os, sys, json",
        "root = sys.argv[1]",
        "SKIP = {'/proc', '/sys', '/dev'}",
        "def dir_size(p):",
        "    total = 0",
        "    for dp, dns, fns in os.walk(p):",
        "        dns[:] = [d for d in dns if os.path.join(dp, d) not in SKIP]",
        "        if dp in SKIP:",
        "            continue",
        "        for fn in fns:",
        "            try:",
        "                total += os.path.getsize(os.path.join(dp, fn))",
        "            except OSError:",
        "                pass",
        "    return total",
        "try:",
        "    names = os.listdir(root)",
        "except OSError as e:",
        "    print(json.dumps({'error': str(e), 'entries': []}))",
        "    sys.exit(0)",
        "entries = []",
        "for name in sorted(names):",
        "    p = os.path.join(root, name)",
        "    if p in SKIP:",
        "        continue",
        "    try:",
        "        is_dir = os.path.isdir(p) and not os.path.islink(p)",
        "        size = dir_size(p) if is_dir else os.path.getsize(p)",
        "    except OSError:",
        "        continue",
        "    entries.append({'path': p, 'name': name, 'size': size, 'isDir': is_dir})",
        "entries.sort(key=lambda e: e['size'], reverse=True)",
        "print(json.dumps({'entries': entries[:200]}))"
    ].join("\n")

    function scan(dir) {
        if (!dir)
            return;
        current = dir;
        scanning = true;
        error = "";
        // a walk of a whole disk can take a while, and one that hangs must not
        // leave the panel waiting forever: Proc gives up after a minute
        Proc.run("disktree-scan", ["python3", "-c", scanScript, dir], (out, code) => {
            root.scanning = false;
            if (code === 124) {
                root.error = "the scan took too long";
                root.entries = [];
                return;
            }
            let r = {};
            try {
                r = JSON.parse(out);
            } catch (e) {
                r = { error: (out || "").trim() || "bad output" };
            }
            if (r.error) {
                root.error = String(r.error);
                root.entries = [];
                return;
            }
            root.entries = r.entries || [];
        }, 0, 60000);
    }
    function refresh() { if (view === "map") scan(current || scanRoot || homeDir()); else findMore(view); }

    // ---- the other views: the biggest files, and duplicates (bridge/dupes.py), of
    //      the folder on screen - marked and trashed the same way as the map's
    readonly property string dupesTool: Quickshell.env("SHANI_DUPES_TOOL") || "/usr/lib/shani-shell/dupes.py"
    property string view: "map"            // map | big | dupes
    property var big: []                   // [{ path, size, mtime }]
    property var dupes: []                 // [{ size, paths: [oldest first] }]
    readonly property real wasted: dupes.reduce((s, g) => s + g.size * (g.paths.length - 1), 0)
    function setView(v) {
        view = v;
        if (v !== "map") findMore(v);
    }
    function findMore(v) {
        scanning = true;
        error = "";
        Proc.run("disktree-" + v, ["python3", dupesTool, v, current || scanRoot || homeDir()], (out, code) => {
            root.scanning = false;
            let r = [];
            try { r = JSON.parse(out); } catch (e) { root.error = code === 124 ? "the scan took too long" : "bad output"; }
            if (v === "big") root.big = r; else root.dupes = r;
        }, 0, 300000);
    }
    // a group's copies all marked but the oldest (the one most likely the original)
    function markExtras(g) { for (const p of g.paths.slice(1)) mark(p); }
    function markAllExtras() { for (const g of dupes) markExtras(g); }

    // ---- navigation: walk into a directory, back out ------------------------
    function enter(path) {
        if (!path)
            return;
        const e = entries.find(x => x.path === path);
        if (!e || !e.isDir)
            return;
        history = history.concat([current]);
        marked = [];  // a mark from another folder must not be trashed here
        scan(path);
    }
    function back() {
        if (!history.length)
            return;
        const prev = history[history.length - 1];
        history = history.slice(0, history.length - 1);
        marked = [];
        scan(prev);
    }
    // the treemap for the panel: rectangles whose area is their size
    function treemap(W, H) { return DiskUsageLogic.treemap(entries, W, H); }
    function humanSize(n) { return Format.humanSize(n); }

    // ---- mark for removal: toggle, review, gio trash -------------------------
    function isMarked(path) { return marked.indexOf(path) >= 0; }
    function toggleMark(path) {
        if (!path)
            return;
        if (isMarked(path))
            marked = marked.filter(p => p !== path);
        else
            marked = marked.concat([path]);
    }
    function mark(path) { if (!isMarked(path)) toggleMark(path); }
    function unmark(path) { if (isMarked(path)) toggleMark(path); }
    function clearMarks() { marked = []; }
    function trashMarked() {
        if (!marked.length)
            return;
        trashProc.command = ["gio", "trash", "--"].concat(marked);
        trashProc.running = true;
    }
    Process {
        id: trashProc
        onExited: code => {
            if (code === 0) {
                root.last = "trashed " + root.marked.length;
                root.marked = [];
                root.refresh();
            } else {
                root.error = "gio trash exited " + code;
            }
        }
    }

    Component.onCompleted: { /* first scan happens on open(), not at startup */ }
}
