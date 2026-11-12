pragma Singleton
// Files: the file manager. The backend (bridge/files.py) does the work - it
// lists a directory, stats a path, makes a folder, renames a file and moves
// something to the trash - and this service holds what the surface shows:
// the folder on screen, the selection, the view, and where it was.
//
// The requests run one after another through one short-lived python process;
// a folder that is watched (the surface and the picker each watch their own)
// keeps that process to itself. So nothing of this runs while the file
// manager is closed.
//
// The trash is the desktop trash (gio trash), so anything moved there can be
// put back from the trash itself - the file manager never deletes.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/FilePaths.js" as FilePaths
import "../Common/FileIcons.js" as FileIcons

Singleton {
    id: root

    readonly property string tool: Quickshell.env("SHANI_FILES_TOOL") || "/usr/lib/shani-shell/files.py"
    readonly property string home: Quickshell.env("HOME") || "/home"
    readonly property var log: Log.scoped("Files")

    // ---- what is on screen ---------------------------------------------------
    property string path: ""                 // the folder being shown
    property var selected: []                // the chosen paths
    property string current: ""              // the one the keyboard is on
    property var history: []                 // the folders visited, oldest first
    property int historyIndex: -1
    property string error: ""

    readonly property bool canBack: historyIndex > 0
    readonly property bool canForward: historyIndex >= 0 && historyIndex < history.length - 1
    readonly property bool canUp: path !== "" && path !== "/" && path !== "recent:"

    // ---- the view ------------------------------------------------------------
    property string viewMode: Settings.data.filesViewMode || "grid"     // grid | list | columns
    property string sortKey: Settings.data.filesSortKey || "name"        // name | size | mtime
    property bool sortDesc: Settings.data.filesSortDesc === true
    property bool showHidden: Settings.data.filesShowHidden === true
    property bool showPreview: Settings.data.filesShowPreview !== false

    // ---- split view: two panes side by side ---------------
    property bool splitActive: false
    property string splitPath: ""
    property var splitSelected: []
    property string splitViewMode: Settings.data.filesViewMode || "grid"

    // ---- the places in the sidebar -------------------------------------------
    property var places: []

    // ---- the requests --------------------------------------------------------
    // One at a time: the answers come back in order, and a directory listing
    // is quick enough that a second one can wait for it.
    property var _queue: []

    function list(path, options, cb) {
        const o = options || {};
        const args = ["list", path];
        if (o.includeHidden) args.push("--hidden");
        if (o.sortKey) args.push("--sort=" + o.sortKey);
        if (o.sortDesc) args.push("--desc");
        if (o.filters && o.filters.length) args.push("--filter=" + o.filters.join(","));
        run(args, cb);
    }

    function stat(path, cb) { run(["stat", path], cb); }

    function mkdir(path, cb) { run(["mkdir", path], cb); }

    function rename(path, name, cb) { run(["rename", path, name], cb); }

    function trash(paths, cb) { run(["trash"].concat(paths || []), cb); }

    function places_(cb) { run(["places"], cb); }

    function run(args, cb) {
        root._queue.push({ "args": args, "cb": cb || function () {} });
        root._next();
    }

    function _next() {
        if (runner.running || root._queue.length === 0)
            return;
        const job = root._queue[0];
        runner.command = ["python3", root.tool].concat(job.args);
        runner.running = true;
        watchdog.restart();
    }

    // a command that hangs must not leave the surface waiting for it
    Timer {
        id: watchdog
        interval: 20000
        onTriggered: {
            root._timedOut = true;
            runner.running = false;
        }
    }

    property bool _timedOut: false

    Process {
        id: runner
        stdout: StdioCollector { id: out }
        onExited: {
            watchdog.stop();
            const job = root._queue.shift();
            if (job) {
                if (root._timedOut) {
                    root.log.error("the file service did not answer:", job.args.join(" "));
                    job.cb({ "error": "the file service did not answer" });
                } else {
                    let r = {};
                    try {
                        r = JSON.parse(out.text);
                    } catch (e) {
                        r = { "error": String(out.text || "").trim() || "the file service said nothing useful" };
                    }
                    if (r.error)
                        root.log.warn(r.error);
                    job.cb(r);
                }
            }
            root._timedOut = false;
            Qt.callLater(root._next);
        }
    }

    // ---- opening and walking -------------------------------------------------
    function show(at) {
        Ui.closeAll();
        Ui.files = true;
        open(at || (path || home));
        loadPlaces();
    }

    function hide() { Ui.files = false; }

    function toggle(at) {
        if (Ui.files) {
            hide();
            return;
        }
        show(at);
    }

    function open(at) {
        const target = FilePaths.normalize(at || "", home);
        if (target === "")
            return;
        root.path = target;
        root.selected = [];
        root.current = "";
        root.error = "";
        if (root.historyIndex < 0 || root.history[root.historyIndex] !== target) {
            root.history = root.history.slice(0, root.historyIndex + 1).concat([target]);
            root.historyIndex = root.history.length - 1;
        }
    }

    function back() {
        if (!root.canBack)
            return;
        root.historyIndex--;
        root.path = root.history[root.historyIndex];
        root.selected = [];
    }

    function forward() {
        if (!root.canForward)
            return;
        root.historyIndex++;
        root.path = root.history[root.historyIndex];
        root.selected = [];
    }

    function up() {
        if (!root.canUp)
            return;
        open(FilePaths.parentOf(root.path));
    }

    // ---- the selection --------------------------------------------------------
    function isSelected(p) { return root.selected.indexOf(p) >= 0; }

    // mode: "single" | "toggle" | "range"
    function select(p, mode) {
        if (!p)
            return;
        // the range runs from where the pointer was, not from where it lands
        const anchor = root.current;
        root.current = p;
        if (mode === "toggle") {
            root.selected = root.isSelected(p) ? root.selected.filter(x => x !== p) : root.selected.concat([p]);
            return;
        }
        if (mode === "range" && anchor !== "") {
            const all = root.entryPaths();
            const from = all.indexOf(anchor);
            const to = all.indexOf(p);
            if (from >= 0 && to >= 0) {
                const lo = Math.min(from, to);
                const hi = Math.max(from, to);
                root.selected = all.slice(lo, hi + 1);
                return;
            }
        }
        root.selected = [p];
    }

    function selectAll() {
        root.selected = root.entryPaths();
    }

    function clearSelection() {
        root.selected = [];
    }

    // the paths on screen, in the order they are shown
    function entryPaths() {
        return root._paths;
    }

    // the panel tells the service what it is showing, so a range selection can
    // follow the order on screen
    property var _paths: []
    function setPaths(paths) { root._paths = paths || []; }

    // ---- changing things ------------------------------------------------------
    function makeFolder(name) {
        if (!FilePaths.validName(name))
            return;
        const target = FilePaths.join(root.path, name.trim());
        root.mkdir(target, function (r) {
            if (r.error) {
                root.error = r.error;
                return;
            }
            root.error = "";
        });
    }

    function renameEntry(p, name) {
        if (!FilePaths.validName(name))
            return;
        root.rename(p, name.trim(), function (r) {
            if (r.error) {
                root.error = r.error;
                return;
            }
            root.error = "";
        });
    }

    function trashEntries(paths) {
        const targets = (paths && paths.length) ? paths : root.selected.slice();
        if (!targets.length)
            return;
        root.trash(targets, function (r) {
            if (r.error) {
                root.error = r.error;
                return;
            }
            root.error = "";
            root.selected = [];
        });
    }

    // ---- opening a file -------------------------------------------------------
    function openEntry(p) {
        if (!p)
            return;
        const e = root.entryFor(p);
        if (e && e.isDir) {
            open(p);
            return;
        }
        Quickshell.execDetached(["xdg-open", p]);
    }

    function openWith(appId, paths) {
        Ui.openFilesWith(appId, paths && paths.length ? paths : root.selected.slice());
    }

    function copyPath(p) {
        if (p)
            Quickshell.clipboardText = p;
    }

    // ---- the view --------------------------------------------------------------
    function setViewMode(mode) {
        root.viewMode = mode;
        Settings.data.filesViewMode = mode;
    }

    function setSort(key) {
        if (root.sortKey === key)
            root.sortDesc = !root.sortDesc;
        else {
            root.sortKey = key;
            root.sortDesc = false;
        }
        Settings.data.filesSortKey = root.sortKey;
        Settings.data.filesSortDesc = root.sortDesc;
    }

    function toggleHidden() {
        root.showHidden = !root.showHidden;
        Settings.data.filesShowHidden = root.showHidden;
    }

    function togglePreview() {
        root.showPreview = !root.showPreview;
        Settings.data.filesShowPreview = root.showPreview;
    }

    // ---- split view ----------------------------------------------------------
    property var _splitPaths: []
    property var _splitEntries: ({})

    function toggleSplit() {
        root.splitActive = !root.splitActive;
        if (root.splitActive && root.splitPath === "")
            root.splitPath = root.path;
    }

    function openInSplit(p) {
        root.splitPath = p;
        root.splitActive = true;
    }

    function toggleSplitViewMode() {
        root.splitViewMode = root.splitViewMode === "grid" ? "list" : "grid";
    }

    function setSplitPaths(paths) { root._splitPaths = paths || []; }
    function setSplitEntries(entries) {
        const map = {};
        for (const e of entries || [])
            map[e.path] = e;
        root._splitEntries = map;
    }

    function isSplitSelected(p) { return root._splitPaths.indexOf(p) >= 0; }

    function selectSplit(p, mode) {
        if (!p) return;
        const s = root._splitPaths;
        if (mode === "single") { root._splitPaths = [p]; root.splitSelected = [p]; return; }
        if (mode === "toggle") {
            const i = s.indexOf(p);
            if (i >= 0) { s.splice(i, 1); }
            else { s.push(p); }
            root._splitPaths = s;
            root.splitSelected = s;
            return;
        }
        if (mode === "range") {
            const i = s.indexOf(p);
            if (i >= 0) { s.splice(i, 1); }
            else { s.push(p); }
            root._splitPaths = s;
            root.splitSelected = s;
        }
    }

    // move selected files from the main pane to the split pane's folder
    function moveToSplit() {
        if (!root.splitActive || root.splitPath === "" || root.selected.length === 0)
            return;
        // argv, never a shell string (a file name is data); -n never writes over what is there
        Quickshell.execDetached(["mv", "-n", "--"].concat(root.selected, [root.splitPath]));
        root.clearSelection();
    }

    // copy selected files from the main pane to the split pane's folder
    function copyToSplit() {
        if (!root.splitActive || root.splitPath === "" || root.selected.length === 0)
            return;
        Quickshell.execDetached(["cp", "-rn", "--"].concat(root.selected, [root.splitPath]));
        root.clearSelection();
    }

    // duplicate a file in the same folder
    function duplicateEntry(p) {
        if (!p) return;
        const e = root.entryFor(p);
        if (!e) return;
        const dir = FilePaths.parentOf(p);
        const base = FilePaths.baseName(p);
        let name = "Copy of " + base;
        let i = 2;
        while (root._entries[FilePaths.join(dir, name)])
            name = "Copy of " + base + " (" + i++ + ")";
        Quickshell.execDetached(["cp", "-rn", "--", p, FilePaths.join(dir, name)]);
    }

    // ---- the places ------------------------------------------------------------
    function loadPlaces() {
        root.places_((r) => { root.places = r.places || []; });
    }

    function entryFor(p) {
        return root._entries[p] || null;
    }

    // the panel hands over what it is showing, so a lookup by path is cheap
    property var _entries: ({})
    property int entryCount: 0
    function setEntries(entries) {
        const map = {};
        for (const e of entries || [])
            map[e.path] = e;
        root._entries = map;
        root.entryCount = Object.keys(map).length;
    }

    // ---- how a file is written about -----------------------------------------
    function baseName(path) { return FilePaths.baseName(path); }

    function parentOf(path) { return FilePaths.parentOf(path); }

    function join(dir, name) { return FilePaths.join(dir, name); }

    // "" when the path is not absolute: nothing sensible can be made of it
    function normalize(path) { return FilePaths.normalize(path, root.home); }

    function validName(name) { return FilePaths.validName(name); }

    function humanSize(bytes) {
        const n = Number(bytes) || 0;
        if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GB";
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB";
        if (n >= 1024) return (n / 1024).toFixed(1) + " KB";
        return n + " B";
    }

    function formatTime(ms) {
        if (!ms)
            return "";
        const d = new Date(ms);
        const now = new Date();
        const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
        if (sameDay)
            return Qt.formatTime(d, "HH:mm");
        if (d.getFullYear() === now.getFullYear())
            return Qt.formatDate(d, "d MMM");
        return Qt.formatDate(d, "d MMM yyyy");
    }

    // the icon a file gets: its kind, not its name
    function iconFor(entry) { return FileIcons.iconFor(entry); }
}
