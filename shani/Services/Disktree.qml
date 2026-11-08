pragma Singleton
// Disktree (disk treemap): what is eating the disk, as rectangles whose
// area is their size. A python3 walk lists a directory's children — sizes
// via os.path.getsize (directories summed by walking them), sorted
// biggest-first, capped at ~200 entries, skipping /proc /sys /dev — and
// Disktree.js lays them out as a treemap of weighted rectangles. Click a
// folder to walk into it (Esc / back to go up), click a file to mark it
// for removal, review the marked list, then move it to the trash with
// `gio trash`. Nothing is deleted until that review is confirmed.
// Shown by Modules/Disktree/DisktreePanel.qml until closed.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "Disktree.js" as DisktreeLogic

Singleton {
    id: root
    property string root: homeDir()        // the scan root (default home)
    property string current: ""            // the directory on screen
    property var entries: []               // [{ path, name, size, isDir }] biggest-first
    property var marked: []                // paths marked for removal, in scan order
    property var history: []               // parent directories, for back()
    property bool scanning: false
    property string error: ""
    property string last: ""               // result of the last trash, for `state`

    readonly property bool shown: Ui.disktree
    readonly property int markedCount: marked.length
    readonly property int totalSize: entries.reduce((s, e) => s + (e.size || 0), 0)

    function homeDir() { return Quickshell.env("HOME") || "/tmp"; }

    function open(dir) {
        Ui.closeAll();
        Ui.disktree = true;
        root = dir || homeDir();
        current = root;
        history = [];
        marked = [];
        error = "";
        scan(root);
    }
    function close() { Ui.disktree = false; }
    function toggle() { root.shown ? close() : open(root || homeDir()); }

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
        scanProc.command = ["python3", "-c", scanScript, dir];
        scanProc.running = true;
    }
    function refresh() { scan(current || root || homeDir()); }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() || "bad output" }; }
                if (r.error) {
                    root.error = String(r.error);
                    root.entries = [];
                    return;
                }
                root.entries = r.entries || [];
            }
        }
        onExited: code => {
            if (code !== 0 && root.scanning) {
                root.scanning = false;
                root.error = "scan exited " + code;
            }
        }
    }

    // ---- navigation: walk into a directory, back out ------------------------
    function enter(path) {
        if (!path)
            return;
        const e = entries.find(x => x.path === path);
        if (!e || !e.isDir)
            return;
        history = history.concat([current]);
        scan(path);
    }
    function back() {
        if (!history.length)
            return;
        const prev = history[history.length - 1];
        history = history.slice(0, history.length - 1);
        scan(prev);
    }
    // the treemap for the panel: rectangles whose area is their size
    function treemap(W, H) { return DisktreeLogic.treemap(entries, W, H); }
    function humanSize(n) {
        n = Number(n) || 0;
        if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GB";
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB";
        if (n >= 1024) return (n / 1024).toFixed(1) + " KB";
        return n + " B";
    }

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
