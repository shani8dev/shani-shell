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
    readonly property bool canUp: path !== "" && path !== "/" && path !== "recent:" && path !== "starred:" && !path.startsWith("kind:")
    // the places that are not folders: their names
    readonly property var kinds: [["pictures", "image-x-generic"], ["music", "audio-x-generic"], ["videos", "video-x-generic"],
                                  ["documents", "x-office-document"], ["archives", "package-x-generic"]]
    function placeTitle(p) {
        if (p === "") return Tr.t("Files");
        if (p === "recent:") return Tr.t("Recent");
        if (p === "starred:") return Tr.t("Starred");
        if (p === "kind:pictures") return Tr.t("All pictures");
        if (p === "kind:music") return Tr.t("All music");
        if (p === "kind:videos") return Tr.t("All videos");
        if (p === "kind:documents") return Tr.t("All documents");
        if (p === "kind:archives") return Tr.t("All archives");
        if (p.endsWith("/.local/share/Trash/files")) return Tr.t("Trash");
        if (/gvfs\/admin/.test(p)) return Tr.t("%1 · as administrator", FilePaths.baseName(p).replace(/^admin[_:]+/, "/") || "/");
        return FilePaths.baseName(p) || "/";
    }

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

    // closed, its passing questions go with it (as a window's dialogs do): only a
    // copy under way, a USB write and a folder open to phones go on
    function hide() { Ui.files = false; }
    Connections { target: Ui; function onFilesChanged() { if (!Ui.files) root._dropDialogs(); } }
    function _dropDialogs() {
        root.historyShown = false;
        root.copyTo = null;
        root.deleteAsk = [];
        root.locker = null;
        root.unlockFor = null;
        root.comparison = null;
        root.props = null;
        if (root.conflictAsk) root.answerConflict("");
        if (!root.usbBusy) root.usb = null;
        if (!root.cloudAdding) root.cloudAsk = false;
    }

    function toggle(at) {
        if (Ui.files) {
            hide();
            return;
        }
        show(at);
    }

    function open(at) {
        // a gvfs place (mtp://, smb://, sftp://, afc://, gphoto2://): its local path
        // under /run/user/<uid>/gvfs, mounted first when it is not yet
        const s = String(at || "");
        if (/^[a-z][a-z0-9+.-]*:\/\//.test(s) && !s.startsWith("file://")) {
            run(["local", s], r => {
                if (r.path) { root.open(r.path); return; }
                run(["mount", s], m => { if (m.path) root.open(m.path); else root.error = m.error || Tr.t("Could not open %1", s); root.loadDevices(); });
            });
            return;
        }
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
    property string _vaultAsked: ""
    function setPaths(paths) {
        root._paths = paths || [];
        // inside an encrypted folder's locked side (gocryptfs.conf is there): its
        // password asked for, to open it
        // (asked once per visit: cancelled, it is not asked again until you come back)
        if (root._paths.some(p => p === root.path + "/gocryptfs.conf") && !root.locker && root._vaultAsked !== root.path) {
            root._vaultAsked = root.path;
            root.askLock("vault-open", root.path);
        }
        if (root._vaultAsked !== root.path && !root._paths.some(p => p === root.path + "/gocryptfs.conf")) root._vaultAsked = "";
    }

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
            if (r.path && r.path !== p)
                root.pushUndo(Tr.t("Renamed to %1", FilePaths.baseName(r.path)), ["move-pairs", JSON.stringify([[r.path, p]])]);
        });
    }

    function trashEntries(paths) {
        const targets = (paths && paths.length) ? paths : root.selected.slice();
        if (!targets.length)
            return;
        root.trash(targets, function (r) {
            if (r.error)
                root.error = r.error;
            else
                root.error = "";
            if (r.pairs && r.pairs.length)
                root.pushUndo(Tr.t("%1 moved to the trash", r.pairs.length), ["restore"].concat(r.pairs.map(x => x[1])));
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
        // an ISO or squashfs: opened as a drive (Disk Image Mounter's job)
        if (/\.(iso|squashfs|sqfs)$/i.test(p)) {
            root.mountImage(p);
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
        root.startJob(root.splitPath, "move", root.selected.slice());
        root.clearSelection();
    }

    // copy selected files from the main pane to the split pane's folder
    function copyToSplit() {
        if (!root.splitActive || root.splitPath === "" || root.selected.length === 0)
            return;
        root.startJob(root.splitPath, "copy", root.selected.slice());
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

    // ---- copying and moving: one job at a time, in a process of its own -------------
    // (files.py job) so a big copy says how far it is, can be stopped, and never
    // holds up the listings and renames the request queue above serves.
    property var _jobs: []                   // [{ dest, mode, paths, after }] still to run
    property bool jobRunning: false
    property string jobMode: ""              // copy | move
    property real jobTotal: 0                // bytes to copy (0: a move that is only renames)
    property real jobDone: 0
    property string jobFile: ""              // the file being copied now
    readonly property real jobFraction: jobTotal > 0 ? Math.min(1, jobDone / jobTotal) : 0
    // TeraCopy's: verify (Settings), a rule for names already there (asked once per
    // job, when there are any), pause, speed and time left, a bad file passed over
    // and retried alone, a queue, what to do when all is done, a history
    property bool jobVerify: Settings.data.filesVerify === true
    function setVerify(on) { Settings.data.filesVerify = on; }
    property bool jobPaused: false
    property real jobRate: 0                 // bytes a second, lately
    property string jobPhase: ""             // "" | verifying
    readonly property real jobSecondsLeft: jobRate > 0 && jobTotal > jobDone ? (jobTotal - jobDone) / jobRate : -1
    readonly property int jobsWaiting: _jobs.length
    property var jobFailed: []               // [{ path, target, error }] of the last job
    property string whenDone: ""             // "" | suspend | poweroff: once the queue is empty
    property var conflictAsk: null           // { dest, mode, paths, after, names } while asked
    function startJob(dest, mode, paths, after, opts) {
        if (!dest || !paths || !paths.length) return;
        // a name already there: asked once for the whole job, as TeraCopy does
        // (its own process: a paste never waits behind a slow listing in the queue)
        if (!opts && (mode === "copy" || mode === "move" || mode === "auto")) {
            root._conflictChecks = root._conflictChecks.concat([{ dest: dest, mode: mode, paths: paths, after: after || null }]);
            root._nextConflictCheck();
            return;
        }
        root._queueJob(dest, mode, paths, after, opts || {});
    }
    property var _conflictChecks: []
    function _nextConflictCheck() {
        if (conflictProc.running || !root._conflictChecks.length) return;
        conflictProc.job = root._conflictChecks[0];
        root._conflictChecks = root._conflictChecks.slice(1);
        conflictProc.command = ["python3", root.tool, "conflicts", conflictProc.job.dest].concat(conflictProc.job.paths);
        conflictProc.running = true;
    }
    Process {
        id: conflictProc
        property var job: null
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                const j = conflictProc.job, names = r.names || [];
                if (names.length) root.conflictAsk = Object.assign({}, j, { names: names });
                else root._queueJob(j.dest, j.mode, j.paths, j.after, {});
                Qt.callLater(root._nextConflictCheck);
            }
        }
    }
    function answerConflict(rule) {
        const c = root.conflictAsk;
        root.conflictAsk = null;
        if (c && rule) root._queueJob(c.dest, c.mode, c.paths, c.after, { conflict: rule });
    }
    function _queueJob(dest, mode, paths, after, opts) {
        if (root.jobVerify && (mode === "copy" || mode === "move" || mode === "auto")) opts.verify = true;
        root._jobs = root._jobs.concat([{ dest: dest, mode: mode, paths: paths, after: after || null, opts: opts }]);
        root._nextJob();
    }
    function pauseJob() { if (jobProc.running) jobProc.signal(10); }      // SIGUSR1: pause / resume
    function retryFailed() {
        const f = root.jobFailed;
        if (!f.length) return;
        root.jobFailed = [];
        root._queueJob("-", root.jobMode === "move" ? "move" : "copy", ["-"], null, { pairs: f.map(x => [x.path, x.target]), conflict: "replace" });
    }
    function makeChecksums(paths) {
        const ps = paths && paths.length ? paths : root.selected.slice();
        if (!ps.length) return;
        const name = (ps.length === 1 ? FilePaths.baseName(ps[0]) : FilePaths.baseName(FilePaths.parentOf(ps[0])) || "checksums") + ".sha256";
        root._queueJob("-", "hash", ps, null, { out: FilePaths.parentOf(ps[0]) + "/" + name });
    }
    function checkChecksums(p) { if (p) root._queueJob("-", "check", [p], null, {}); }
    function isChecksumFile(p) { return /\.(sha256|sha1|sha512|md5)$/i.test(p || "") || /(SHA256|SHA1|SHA512|MD5)SUMS$/.test(p || ""); }
    property var lastCheck: null
    property var copyHistory: []
    function loadCopyHistory() { run(["copy-history"], r => { root.copyHistory = r.history || []; }); }
    property bool historyShown: false
    // Copy to… / Move to…: a folder picked (the ones used lately first)
    property var copyTo: null                // { mode, paths } while asked
    readonly property var recentDests: Settings.data.filesRecentDests || []
    function sendTo(mode, dest) {
        const c = root.copyTo;
        root.copyTo = null;
        if (!c || !dest) return;
        Settings.data.filesRecentDests = [dest].concat(root.recentDests.filter(x => x !== dest)).slice(0, 6);
        root.startJob(dest, mode, c.paths);
    }
    function _nextJob() {
        if (root.jobRunning || !root._jobs.length) return;
        const j = root._jobs[0];
        root._jobs = root._jobs.slice(1);
        root._job = j;
        root.jobMode = j.mode;
        root.jobTotal = 0;
        root.jobDone = 0;
        root.jobFile = "";
        root.jobPaused = false;
        root.jobRate = 0;
        root.jobPhase = "";
        root.jobRunning = true;
        jobProc.command = ["python3", root.tool, "job", j.dest, j.mode, "--opts=" + JSON.stringify(j.opts || {})].concat(j.paths);
        jobProc.running = true;
    }
    property var _job: null
    property var _jobResult: null
    function cancelJob() {
        if (jobProc.running) jobProc.signal(15);           // the half-written one is removed, the rest stay
        root._jobs = [];
    }
    Process {
        id: jobProc
        stdout: SplitParser {
            onRead: line => {
                let r;
                try { r = JSON.parse(line); } catch (e) { return; }
                if (r.pairs !== undefined) { root._jobResult = r; return; }
                if (r.paused !== undefined) root.jobPaused = r.paused;
                if (r.phase !== undefined) { root.jobPhase = r.phase; root.jobFile = r.file || root.jobFile; }
                if (r.total !== undefined) root.jobTotal = r.total;
                if (r.done !== undefined) { root.jobDone = r.done; root.jobFile = r.file || ""; root.jobPhase = ""; }
                if (r.rate !== undefined) root.jobRate = r.rate;
            }
        }
        onExited: {
            const j = root._job, r = root._jobResult || { error: Tr.t("the copy stopped") };
            root._jobResult = null;
            root.jobRunning = false;
            root.error = r.error || "";
            root.jobFailed = r.failed || [];
            root.jobPaused = false;
            // what the checksums said
            if (j && j.mode === "hash" && r.saved) { root.note = Tr.t("Checksums of %1 files in %2", r.count || 0, FilePaths.baseName(r.saved)); }
            if (j && j.mode === "check" && r.good !== undefined) {
                root.lastCheck = r;
                root.note = (r.bad || []).length || (r.missing || []).length ? Tr.t("%1 match, %2 do not, %3 missing", r.good, (r.bad || []).length, (r.missing || []).length)
                                                                            : Tr.t("All %1 match", r.good);
            }
            // a partly done one has no Undo: what failed is listed, with Retry
            const pairs = (r.pairs || []).filter(x => x[2] === "moved" || x[2] === "copied");
            if ((r.replaced || 0) > 0) root.note = Tr.t("%1 replaced - the ones they replaced are in the trash", r.replaced);
            // each item says what was done to it (a drop moves some, copies others)
            const moved = pairs.filter(x => x[2] === "moved"), copied = pairs.filter(x => x[2] !== "moved");
            if (moved.length && !copied.length)
                root.pushUndo(Tr.t("%1 moved here", moved.length), ["move-pairs", JSON.stringify(moved.map(x => [x[1], x[0]]))]);
            else if (copied.length && !moved.length)
                root.pushUndo(Tr.t("%1 copied here", copied.length), ["trash"].concat(copied.map(x => x[1])));
            else if (pairs.length) {
                // both: two undo steps, the copies' last so Ctrl+Z takes them first
                root.pushUndo(Tr.t("%1 moved here", moved.length), ["move-pairs", JSON.stringify(moved.map(x => [x[1], x[0]]))]);
                root.pushUndo(Tr.t("%1 copied here", copied.length), ["trash"].concat(copied.map(x => x[1])));
            }
            if (r.cancelled) root.note = Tr.t("Stopped: %1 finished before that", pairs.length);
            if (j && j.after) j.after(pairs);
            Qt.callLater(root._nextJob);
            // the whole queue done, nothing failed: what was asked for then
            if (!root._jobs.length && root.whenDone && !root.jobFailed.length && !r.cancelled) {
                const what = root.whenDone;
                root.whenDone = "";
                Quickshell.execDetached(["systemctl", what]);
            }
        }
    }

    // ---- in a terminal, from a template, as the wallpaper ---------------------------
    // the desktop's terminal (xdg-terminal-exec: foot here), started inside the folder,
    // so any terminal opens there - no flag of one terminal's own
    function openTerminal(dir) {
        const d = dir || root.path;
        if (!d || !d.startsWith("/")) return;
        Quickshell.execDetached(["sh", "-c", 'cd -- "$1" && exec xdg-terminal-exec', "sh", d]);
    }
    property var templates: []               // [{ name, path }]: ~/Templates' files
    function loadTemplates() { run(["templates"], r => { root.templates = r.templates || []; }); }
    function newFromTemplate(tpl, dest) {
        const d = dest || root.path;
        if (!tpl || !d.startsWith("/")) return;
        run(["paste", d, "copy", tpl.path], r => {
            root.error = r.error || "";
            const pairs = r.pairs || [];
            if (pairs.length) {
                root.pushUndo(Tr.t("New %1", tpl.name), ["trash"].concat(pairs.map(x => x[1])));
                root.select(pairs[0][1], "single");
            }
        });
    }
    function setWallpaper(p) {
        if (!p) return;
        Settings.data.wallpaper = p;
        root.note = Tr.t("%1 is the wallpaper now", FilePaths.baseName(p));
    }

    // ---- the selection turned over; how big the tiles are ---------------------------
    function invertSelection() {
        root.selected = root._paths.filter(p => root.selected.indexOf(p) < 0);
    }
    property real zoom: Settings.data.filesZoom || 1
    function setZoom(z) {
        root.zoom = Math.max(0.6, Math.min(2.2, Math.round(z * 10) / 10));
        Settings.data.filesZoom = root.zoom;
    }

    // ---- stars: kept with the shell (files.py starred), wherever the files are -------
    property var starred: []
    function loadStarred() { run(["starred-list"], r => { root.starred = r.starred || []; }); }
    function isStarred(p) { return root.starred.indexOf(p) >= 0; }
    function setStar(paths, on) {
        const ps = paths && paths.length ? paths : root.selected.slice();
        if (!ps.length) return;
        run([on ? "star-add" : "star-remove"].concat(ps), r => { root.starred = r.starred || []; });
    }

    // ---- rights: who may read, change and run it (files.py chmod-pairs, with undo) ----
    function setRights(pairs, label) {
        if (!pairs || !pairs.length) return;
        run(["chmod-pairs", JSON.stringify(pairs)], r => {
            root.error = r.error || "";
            if (r.pairs && r.pairs.length) {
                root.pushUndo(label || Tr.t("Rights changed"), ["chmod-pairs", JSON.stringify(r.pairs)]);
                if (root.props && root.props.path) root.showProps([root.props.path]);
            }
        });
    }

    // ---- free space on the drive of the folder on screen -----------------------------
    property real freeBytes: -1
    onPathChanged: if (root.path.startsWith("/")) run(["free", root.path], r => { root.freeBytes = r.free !== undefined ? r.free : -1; }); else root.freeBytes = -1

    // ---- tabs: each its own folder; the one on screen is Files.path ------------------
    property var tabs: []                    // the other tabs' folders; [] = one tab (no tab bar)
    property int tabIndex: 0
    readonly property var tabPaths: tabs.length ? tabs.map((p, i) => i === tabIndex ? root.path : p) : [root.path]
    function newTab(at) {
        const all = root.tabPaths.slice();
        all.splice(root.tabIndex + 1, 0, at || root.path);
        root.tabs = all;
        root.tabIndex = root.tabIndex + 1;
        root.open(all[root.tabIndex]);
    }
    function switchTab(i) {
        if (!root.tabs.length || i < 0 || i >= root.tabs.length || i === root.tabIndex) return;
        const all = root.tabPaths.slice();
        root.tabs = all;
        root.tabIndex = i;
        root.open(all[i]);
    }
    function closeTab(i) {
        const all = root.tabPaths.slice();
        if (all.length <= 1) { root.hide(); return; }
        const at = i === undefined ? root.tabIndex : i;
        all.splice(at, 1);
        const next = Math.min(at <= root.tabIndex ? Math.max(0, root.tabIndex - (at < root.tabIndex ? 1 : 0)) : root.tabIndex, all.length - 1);
        root.tabs = all.length > 1 ? all : [];
        root.tabIndex = all.length > 1 ? next : 0;
        root.open(all[all.length > 1 ? next : 0]);
    }

    // ---- thumbnails: a video's frame, a PDF's first page (files.py thumbs) -----------
    // asked for when a folder is listed; a new folder stops the last folder's asking
    property var thumbs: ({})                 // path -> thumbnail PNG
    function requestThumbs(paths) {
        thumbProc.running = false;
        const ps = (paths || []).slice(0, 400);
        if (!ps.length) return;
        thumbProc.command = ["python3", root.tool, "thumbs", "normal"].concat(ps);
        thumbProc.running = true;
    }
    Process {
        id: thumbProc
        stdout: SplitParser {
            onRead: line => {
                let r;
                try { r = JSON.parse(line); } catch (e) { return; }
                if (!r.path || !r.thumb) return;
                const m = Object.assign({}, root.thumbs);
                m[r.path] = r.thumb;
                root.thumbs = m;
            }
        }
    }

    // ---- drag and drop -----------------------------------------------------------------
    // what a drag carries: the selection when the dragged file is part of it, else that file
    function dragUris(p) {
        const ps = root.isSelected(p) ? root.selected.slice() : [p];
        return ps.map(root.uriOf).join("\r\n") + "\r\n";
    }
    // a drop: local files only (a browser's link is not a file); "auto" moves on the
    // same drive and copies from another (files.py job decides, per item)
    function dropUrls(dest, urls, mode) {
        const paths = Array.from(urls || []).map(String).filter(u => u.startsWith("file://"))
            .map(u => decodeURIComponent(u.slice(7)))
            .filter(p => p !== dest && FilePaths.parentOf(p) !== dest);    // onto itself, or where it is: nothing
        if (!paths.length || !dest) return 0;
        root.startJob(dest, mode || "auto", paths);
        return paths.length;
    }

    // ---- undo: what was done, and the moves that put it back -----------------------
    property var undoStack: []               // [{ label, inverse: files.py argv }]
    readonly property string undoLabel: undoStack.length ? undoStack[undoStack.length - 1].label : ""
    property string note: ""                 // what was just done, shown with Undo
    function pushUndo(label, inverse, keepRedo) {
        undoStack = undoStack.concat([{ label: label, inverse: inverse }]).slice(-20);
        if (!keepRedo) redoStack = [];       // a new change: what was undone cannot come back
        note = label;
    }
    // Redo (Ctrl+Shift+Z, Ctrl+Y): each undo says what it did, and that, turned
    // round, is the redo - moved back is moved again, put back is trashed again
    property var redoStack: []
    readonly property string redoLabel: redoStack.length ? redoStack[redoStack.length - 1].label : ""
    function _turned(cmd, r) {
        const ps = r.pairs || [];
        if (!ps.length) return null;
        if (cmd === "move-pairs") return ["move-pairs", JSON.stringify(ps.map(x => [x[1], x[0]]))];
        if (cmd === "trash") return ["restore"].concat(ps.map(x => x[1]));
        if (cmd === "restore") return ["trash"].concat(ps.map(x => x[1]));
        if (cmd === "chmod-pairs") return ["chmod-pairs", JSON.stringify(ps)];
        return null;
    }
    function undo() {
        if (!undoStack.length) return;
        const u = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        run(u.inverse, r => {
            root.error = r.error || "";
            root.note = r.error ? "" : Tr.t("Undone: %1", u.label);
            const back = root._turned(u.inverse[0], r);
            if (back) root.redoStack = root.redoStack.concat([{ label: u.label, again: back }]).slice(-20);
            if (root.isTrash) root.loadTrash();
        });
    }
    function redo() {
        if (!redoStack.length) return;
        const d = redoStack[redoStack.length - 1];
        redoStack = redoStack.slice(0, -1);
        run(d.again, r => {
            root.error = r.error || "";
            const back = root._turned(d.again[0], r);
            if (back) root.pushUndo(d.label, back, true);
            root.note = r.error ? "" : Tr.t("Done again: %1", d.label);
            if (root.isTrash) root.loadTrash();
        });
    }

    // ---- Shift+Delete: gone for good (asked first) - moved to the trash, then just
    //      those taken out of it; never the rest of the trash
    property var deleteAsk: []
    function deleteNow(paths) {
        const ps = paths && paths.length ? paths : root.selected.slice();
        if (!ps.length) return;
        root.deleteAsk = [];
        root.trash(ps, r => {
            const names = (r.pairs || []).map(x => x[1]).filter(n => n);
            if (!names.length) { root.error = r.error || Tr.t("Nothing was deleted"); return; }
            run(["empty-trash"].concat(names), e => { root.note = Tr.t("%1 deleted for good", e.removed || names.length); });
            root.selected = [];
        });
    }

    // ---- Nautilus scripts (~/.local/share/nautilus/scripts): each one a menu item,
    //      run in the folder with the chosen files, as Nautilus runs them
    property var scripts: []
    function loadScripts() { run(["scripts"], r => { root.scripts = r.scripts || []; }); }
    function runScript(s, paths) {
        const ps = paths && paths.length ? paths : root.selected.slice();
        Quickshell.execDetached(["sh", "-c", 'cd -- "$1" || exit 1; s=$2; shift 2
            NAUTILUS_SCRIPT_SELECTED_FILE_PATHS=$(printf "%s\n" "$@") NAUTILUS_SCRIPT_SELECTED_URIS=$(for f; do printf "file://%s\n" "$f"; done) \
            NAUTILUS_SCRIPT_CURRENT_URI="file://$PWD" exec "$s" "$@"', "sh", root.path, s.path].concat(ps));
        root.note = Tr.t("%1 started", s.name);
    }

    // ---- copy, cut and paste: the desktop's file clipboard ------------------------
    // the formats GNOME Files and GTK apps read: a copy is text/uri-list, a cut is
    // x-special/gnome-copied-files ("cut" and the URIs), so files go both ways
    function uriOf(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }
    function toClipboard(mode, paths) {
        const ps = paths && paths.length ? paths : root.selected.slice();
        if (!ps.length) return;
        const uris = ps.map(root.uriOf).join("\n");
        if (mode === "cut")
            Quickshell.execDetached(["wl-copy", "--type", "x-special/gnome-copied-files", "--", "cut\n" + uris]);
        else
            Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", "--", uris]);
        root.note = mode === "cut" ? Tr.t("%1 to move: paste where they go", ps.length) : Tr.t("%1 copied: paste where they go", ps.length);
    }
    function pasteHere(dest) {
        pasteReader.dest = dest || root.path;
        if (!pasteReader.dest || pasteReader.dest.indexOf(":") >= 0 && !pasteReader.dest.startsWith("/")) return;
        pasteReader.running = true;
    }
    Process {
        id: pasteReader
        property string dest: ""
        command: ["sh", "-c", 'T=$(wl-paste --list-types 2>/dev/null); if printf "%s\n" "$T" | grep -qx x-special/gnome-copied-files; then wl-paste -n --type x-special/gnome-copied-files; elif printf "%s\n" "$T" | grep -qx text/uri-list; then printf "copy\n"; wl-paste -n --type text/uri-list; fi']
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split(/\r?\n/).filter(l => l);
                if (!lines.length) { root.note = Tr.t("Nothing to paste: copy some files first"); return; }
                const mode = lines[0] === "cut" ? "move" : "copy";
                const paths = lines.slice(1).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)));
                if (!paths.length) return;
                root.startJob(pasteReader.dest, mode, paths, pairs => {
                    if (mode === "move" && pairs.length)
                        Quickshell.execDetached(["wl-copy", "--clear"]);       // a cut is pasted once
                });
            }
        }
    }

    // ---- the trash: what came from where, put back, emptied ----------------------
    readonly property string trashFiles: (Quickshell.env("XDG_DATA_HOME") || root.home + "/.local/share") + "/Trash/files"
    readonly property bool isTrash: root.path === root.trashFiles
    property var trashItems: ({})            // name -> { original, deleted }
    function loadTrash() {
        run(["trash-list"], r => {
            const m = {};
            for (const it of r.items || []) m[it.name] = it;
            root.trashItems = m;
        });
    }
    onIsTrashChanged: if (isTrash) loadTrash()
    function trashNameOf(p) { return FilePaths.baseName(p); }
    function putBack(paths) {
        const names = (paths && paths.length ? paths : root.selected).map(root.trashNameOf);
        run(["restore"].concat(names), r => {
            root.error = r.error || "";
            if (r.pairs && r.pairs.length) {
                root.note = Tr.t("%1 put back where they were", r.pairs.length);
                root.pushUndo(Tr.t("%1 put back", r.pairs.length), ["trash"].concat(r.pairs.map(x => x[1])));
            }
            root.loadTrash();
        });
    }
    // for good: no undo, so the window asks twice
    function deleteForGood(paths) {
        const names = (paths && paths.length ? paths : root.selected).map(root.trashNameOf);
        run(["empty-trash"].concat(names), r => { root.note = Tr.t("%1 deleted for good", r.removed || 0); root.loadTrash(); });
    }
    function emptyTrash() {
        run(["empty-trash"], r => { root.note = Tr.t("The trash is empty"); root.loadTrash(); });
    }

    // ---- bookmarks: GTK's file, so GTK apps' sidebars have them too ---------------
    function isBookmarked(p) { return root.places.some(x => x.bookmark && x.path === p); }
    function setBookmark(p, on) { run([on ? "bookmark-add" : "bookmark-remove", p], () => root.loadPlaces()); }

    // ---- Properties ------------------------------------------------------------------
    property var props: null                 // what files.py props answered, while shown
    function showProps(paths) {
        const ps = paths && paths.length ? paths : root.selected.slice();
        if (!ps.length) return;
        root.props = { loading: true, count: ps.length };
        run(["props"].concat(ps), r => { root.props = r; });
    }

    // ---- a folder shared on the local network (Samba usershares, as Settings >
    //      Sharing and Nautilus's "Sharing Options"): others read it, with a login;
    //      who may change files is set in Settings > Sharing
    property var shares: ({})                // path -> share name
    function loadShares() { sharesProc.running = true; }
    Process {
        id: sharesProc
        command: ["sh", "-c", "command -v net >/dev/null && net usershare info 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                let name = "";
                for (const l of text.split("\n")) {
                    let m = /^\[(.+)\]$/.exec(l);
                    if (m) name = m[1];
                    m = /^path=(.*)$/.exec(l);
                    if (m && name) out[m[1].replace(/\/+$/, "")] = name;
                }
                root.shares = out;
            }
        }
    }
    function isShared(p) { return root.shares[p] !== undefined; }
    function setShared(p, on) {
        if (!p || shareProc.running) return;
        const name = on ? (FilePaths.baseName(p).replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 60) || "share") : root.shares[p];
        shareProc.what = on ? Tr.t("%1 is shared on the network as %2", FilePaths.baseName(p), name) : Tr.t("%1 is no longer shared", FilePaths.baseName(p));
        shareProc.command = on ? ["net", "usershare", "add", name, p, "", "Everyone:R", "guest_ok=n"] : ["net", "usershare", "delete", name];
        shareProc.running = true;
    }
    Process {
        id: shareProc
        property string what: ""
        stderr: StdioCollector { id: shareErr }
        onExited: code => {
            if (code === 0) root.note = shareProc.what;
            else root.error = shareErr.text.trim().split("\n").pop() || Tr.t("Sharing needs the sambashare group (Settings > Sharing)");
            root.loadShares();
        root.loadClouds();
        root.loadScripts();
        }
    }

    // ---- locked with a password: a PDF (a PDF password), any other file or a
    //      folder (sealed with gpg), an encrypted folder (gocryptfs) - lock.py, the
    //      password on its stdin. One dialog for all of them.
    readonly property string lockTool: Quickshell.env("SHANI_LOCK_TOOL") || "/usr/lib/shani-shell/lock.py"
    property var locker: null                // { mode: lock|unlock|vault-new|vault-open, path } while asked
    property string lockError: ""
    property string lockResult: ""           // the last one made, for the tests
    readonly property bool lockBusy: lockProc.running
    function askLock(mode, path) { if (path) { root.locker = { mode: mode, path: path }; root.lockError = ""; root.lockAsZip = true; } }
    // anything but a PDF: a ZIP with a password (opens on any computer) or sealed with gpg
    property bool lockAsZip: true
    function isGpg(p) { return /\.gpg$/i.test(p || ""); }
    function doLock(password, extra) {
        const l = root.locker;
        if (!l || !password || lockProc.running) return;
        root.lockError = "";
        const target = l.mode === "vault-new" ? l.path + "/" + (extra || "").replace(/\//g, "_") : l.path;
        lockProc.mode = l.mode;
        lockProc.payload = password;
        lockProc.command = ["python3", root.lockTool, l.mode, target].concat(l.mode === "lock" && extra === true ? ["--trash"] : [])
                                                                      .concat(l.mode === "lock" && root.lockAsZip && !/\.pdf$/i.test(target) ? ["--zip"] : []);
        lockProc.running = true;
    }
    Process {
        id: lockProc
        property string mode: ""
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = ""; }
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() || Tr.t("That did not work") }; }
                if (r.wrongPassword) { root.lockError = Tr.t("That password did not open it"); return; }
                if (r.error) { root.lockError = r.error; return; }
                root.locker = null;
                root.lockResult = r.saved || "";
                const name = FilePaths.baseName(r.saved || "");
                if (lockProc.mode === "vault-open") { root.open(r.saved); root.loadDevices(); return; }
                root.note = lockProc.mode === "lock" ? Tr.t("Locked: %1", name) : lockProc.mode === "vault-new" ? Tr.t("%1 made: open it to put files in", name) : Tr.t("Unlocked: %1", name);
                if (r.saved) Qt.callLater(() => root.select(r.saved, "single"));
            }
        }
    }

    // ---- as the administrator (Nautilus's "Open as Administrator"): gvfs's admin://,
    //      whose helper asks polkit - the shell's own agent shows the question - and
    //      then reads and writes as root for this session; Files itself stays yours.
    //      A folder opens in Files, a file in its app, through gvfs's FUSE path.
    function openAsAdmin(p, isDir) {
        if (!p || !p.startsWith("/")) return;
        const uri = "admin://" + p;
        if (isDir) { root.open(uri); return; }
        run(["local", uri], r => {
            if (r.path) { Quickshell.execDetached(["xdg-open", r.path]); return; }
            run(["mount", uri], m => {
                if (!m.path) { root.error = m.error || Tr.t("Could not open %1 as the administrator", FilePaths.baseName(p)); return; }
                run(["local", uri], l => { if (l.path) Quickshell.execDetached(["xdg-open", l.path]); else root.error = Tr.t("Could not open %1 as the administrator", FilePaths.baseName(p)); });
            });
        });
    }
    readonly property bool asAdmin: /gvfs\/admin/.test(root.path)

    // ---- cloud drives (cloud.py: rclone): listed in the sidebar, opened (mounted)
    //      with a click, added with the provider's own sign-in in the browser
    readonly property string cloudTool: Quickshell.env("SHANI_CLOUD_TOOL") || "/usr/lib/shani-shell/cloud.py"
    property var clouds: []
    property bool cloudAdding: false
    property string cloudError: ""
    function loadClouds() { cloudList.running = true; }
    Process {
        id: cloudList
        command: ["python3", root.cloudTool, "list"]
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); root.clouds = Array.isArray(r) ? r : []; } catch (e) { root.clouds = []; } } }
    }
    function openCloud(c) {
        if (!c) return;
        if (c.mounted) { root.open(c.path); return; }
        root.busyDevice = c.name;
        cloudRun.after = r => { root.busyDevice = ""; if (r.path) { root.open(r.path); root.loadDevices(); } else root.error = r.error || Tr.t("Could not open %1", c.name); root.loadClouds(); };
        cloudRun.payload = "";
        cloudRun.command = ["python3", root.cloudTool, "mount", c.name];
        cloudRun.running = true;
    }
    function addCloud(name, kind, url, user, password) {
        if (cloudRun.running) return;
        root.cloudAdding = true;
        root.cloudError = "";
        cloudRun.after = r => {
            root.cloudAdding = false;
            if (r.ok) { root.note = Tr.t("%1 added", name); root.loadClouds(); root.cloudAsk = false; }
            else root.cloudError = r.error || Tr.t("That did not work");
        };
        cloudRun.payload = kind === "webdav" ? JSON.stringify({ url: url || "", user: user || "", password: password || "" }) : "";
        cloudRun.command = ["python3", root.cloudTool, "add", name, kind];
        cloudRun.running = true;
    }
    function forgetCloud(c) {
        if (!c || cloudRun.running) return;
        cloudRun.after = r => { if (r.error) root.error = r.error; else root.note = Tr.t("%1 removed from this computer", c.name); root.loadClouds(); root.loadDevices(); };
        cloudRun.payload = "";
        cloudRun.command = ["python3", root.cloudTool, "remove", c.name];
        cloudRun.running = true;
    }
    property bool cloudAsk: false            // the Add dialog
    Process {
        id: cloudRun
        property var after: null
        property string payload: ""
        stdinEnabled: true
        onStarted: { if (payload) write(payload + "\n"); payload = ""; }
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() || Tr.t("That did not work") }; }
                if (cloudRun.after) cloudRun.after(r);
            }
        }
    }

    // ---- a folder opened to phones on this network for a while (serve.py): a link
    //      behind a secret, shown as a QR code; its port opened in the firewall
    //      only while it runs (as Nearby does for LocalSend)
    readonly property string serveTool: Quickshell.env("SHANI_SERVE_TOOL") || "/usr/lib/shani-shell/serve.py"
    readonly property string firewallCmd: Quickshell.env("SHANI_FIREWALL_CMD") || "firewall-cmd"
    readonly property int servePort: parseInt(Quickshell.env("SHANI_SERVE_PORT") || "53318")
    property string servedPath: ""
    property string servedUrl: ""
    property bool servedUpload: false
    property int servedGot: 0                // files phones added
    function serveFolder(p, upload) {
        if (!p || !p.startsWith("/") || serveProc.running) return;
        root.servedPath = p; root.servedUpload = !!upload; root.servedUrl = ""; root.servedGot = 0;
        serveFw.command = ["sh", "-c", '"$1" --state >/dev/null 2>&1 || exit 0; "$1" --add-port="$2"/tcp', "sh", root.firewallCmd, String(root.servePort)];
        serveFw.then = true;
        serveFw.running = true;
    }
    function stopServing() {
        if (serveProc.running) serveProc.signal(15);
    }
    Process {
        id: serveFw
        property bool then: false
        onExited: if (then) {
            then = false;
            serveProc.command = ["python3", root.serveTool, root.servedPath].concat(root.servedUpload ? ["--upload"] : []);
            serveProc.running = true;
        }
    }
    Process {
        id: serveProc
        stdout: SplitParser {
            onRead: line => {
                let r;
                try { r = JSON.parse(line); } catch (e) { return; }
                if (r.url) { root.servedUrl = r.url; Qr.show(Tr.t("Open %1 on your phone", FilePaths.baseName(root.servedPath)), r.url); }
                if (r.error) root.error = r.error;
                if (r.got) { root.servedGot++; root.note = Tr.t("A phone added %1", FilePaths.baseName(r.got)); }
            }
        }
        onExited: {
            if (Qr.text === root.servedUrl && root.servedUrl) Qr.close();      // its own code only
            root.servedUrl = "";
            root.servedPath = "";
            serveFw.command = ["sh", "-c", '"$1" --state >/dev/null 2>&1 || exit 0; "$1" --remove-port="$2"/tcp', "sh", root.firewallCmd, String(root.servePort)];
            serveFw.running = true;
        }
    }

    // ---- two compared (Meld's job): texts line by line, folders by what differs ------
    property var comparison: null            // files.py compare's answer plus a, b; while shown
    // merging (Meld): a change's lines copied to the other side; then that side saved
    property var compareEdited: ({ l: false, r: false })
    function compareTake(start, toRight) {
        const c = root.comparison;
        if (!c || !c.rows) return;
        const rows = c.rows.slice();
        for (let i = start; i < rows.length && rows[i].tag !== "equal"; i++) {
            const x = Object.assign({}, rows[i]);
            if (toRight) x.r = x.l; else x.l = x.r;
            x.tag = "equal";
            x.merged = true;
            rows[i] = x;
        }
        root.comparison = Object.assign({}, c, { rows: rows, changes: Math.max(0, (c.changes || 1) - 1) });
        root.compareEdited = Object.assign({}, root.compareEdited, toRight ? { r: true } : { l: true });
    }
    function compareSave(right) {
        const c = root.comparison;
        if (!c || !c.rows) return;
        const text = c.rows.map(x => right ? x.r : x.l).filter(x => x !== null && x !== undefined).join("\n") + "\n";
        compareSaver.payload = text;
        compareSaver.which = right ? "r" : "l";
        compareSaver.command = ["python3", root.tool, "compare-save", right ? c.b : c.a];
        compareSaver.stdinEnabled = true;
        compareSaver.running = true;
    }
    Process {
        id: compareSaver
        property string payload: ""
        property string which: ""
        onStarted: { write(payload); payload = ""; stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                if (r.saved) {
                    root.note = Tr.t("%1 saved - its old version is in the trash", FilePaths.baseName(r.saved));
                    const e = Object.assign({}, root.compareEdited); e[compareSaver.which] = false; root.compareEdited = e;
                } else root.error = r.error || Tr.t("That did not work");
            }
        }
    }
    function compare(a, b) {
        root.compareEdited = { l: false, r: false };
        if (!a || !b) return;
        root.comparison = { loading: true, a: a, b: b };
        run(["compare", a, b], r => { r.a = a; r.b = b; root.comparison = r; });
    }

    // ---- several renamed at once: "Holiday #" -> Holiday 1, Holiday 2 ... ------------
    function batchRename(pattern, paths) {
        const ps = paths && paths.length ? paths : root.selected.slice();
        if (ps.length < 2 || !pattern.trim()) return;
        run(["batch-rename", pattern].concat(ps), r => {
            root.error = r.error || "";
            if (r.pairs && r.pairs.length) {
                root.pushUndo(Tr.t("%1 renamed", r.pairs.length), ["move-pairs", JSON.stringify(r.pairs.map(x => [x[1], x[0]]))]);
                root.selected = [];
            }
        });
    }

    // ---- search through the folder and every folder under it ----------------------
    property string searchText: ""           // the search box's words (IPC sets them too)
    property bool searchDeep: Settings.data.filesSearchDeep === true
    function setSearchDeep(on) { root.searchDeep = on; Settings.data.filesSearchDeep = on; }
    function searchPath(words) { return "search:" + words + "\t" + (root.path.startsWith("/") ? root.path : root.home); }

    // ---- the places ------------------------------------------------------------
    function loadPlaces() {
        root.places_((r) => { root.places = r.places || []; });
        root.loadDevices();
        root.loadStarred();
        root.loadTemplates();
        root.loadShares();
    }

    // ---- drives, phones, cameras, network places (gio) ------------------------------
    property var devices: []                 // [{ name, path, mounted, mount, icon, internal, canEject, canUnmount, network }]
    property string busyDevice: ""           // the one being mounted or ejected now
    function loadDevices() { run(["devices"], r => { root.devices = r.devices || []; }); }
    Connections { target: Plugged; function onStorageRevChanged() { if (Ui.files) root.loadDevices(); } }
    function openDevice(d) {
        if (!d) return;
        if (d.mounted && d.path) { root.open(d.path); return; }
        root.busyDevice = d.mount;
        run(["mount", d.mount], r => {
            root.busyDevice = "";
            if (r.path) root.open(r.path);
            else if (r.needsPassword) { root.unlockFor = d; root.unlockError = ""; }
            else root.error = r.error || Tr.t("Could not open %1", d.name);
            root.loadDevices();
        });
    }
    // an encrypted drive: its password asked for, handed to gio on stdin
    property var unlockFor: null
    property string unlockError: ""
    function unlockDevice(password) {
        const d = root.unlockFor;
        if (!d || unlockProc.running) return;
        root.busyDevice = d.mount;
        unlockProc.payload = JSON.stringify({ password: password || "" });
        unlockProc.command = ["python3", root.tool, "unlock", d.mount];
        unlockProc.stdinEnabled = true;
        unlockProc.running = true;
    }
    Process {
        id: unlockProc
        property string payload: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                root.busyDevice = "";
                if (r.path) { root.unlockFor = null; root.open(r.path); root.loadDevices(); }
                else root.unlockError = r.needsPassword ? Tr.t("That password did not open it") : (r.error || Tr.t("That did not work"));
            }
        }
        onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false; }
    }
    function ejectDevice(d) {
        if (!d || !d.path) return;
        root.busyDevice = d.mount;
        run([d.canEject ? "eject" : "unmount", d.path], r => {
            root.busyDevice = "";
            if (r.error) root.error = r.error;
            else {
                root.note = d.canEject ? Tr.t("%1 can be taken out now", d.name) : Tr.t("%1 is closed", d.name);
                if (root.path === d.path || root.path.startsWith(d.path + "/")) root.open(root.home);
            }
            root.loadDevices();
        });
    }
    // ---- USB drives (Impression's and GNOME Disks' jobs): a disk image written to
    //      one, or one formatted - udisks2 through drives.py, its polkit question
    //      answered in the shell's own agent. Asked for by typing the drive's name.
    readonly property string drivesTool: Quickshell.env("SHANI_DRIVES_TOOL") || "/usr/lib/shani-shell/drives.py"
    property var usb: null                   // { mode: write|format, image, drives, loading } while the dialog is up
    property bool usbBusy: false
    property real usbDone: 0
    property real usbTotal: 0
    property string usbError: ""
    property string usbResult: ""            // what the last one did, for the tests
    function diskImage(p) { return /\.(iso|img|raw)(\.(xz|gz|bz2|zst))?$/i.test(p || ""); }
    function mountableImage(p) { return /\.(iso|img|raw|squashfs|sqfs)$/i.test(p || ""); }
    // a disk image opened read-only as a drive; it shows under Devices, Eject lets it go
    property string imageMounted: ""         // where the last one opened, for the tests
    function mountImage(p) {
        if (!p || imgProc.running) return;
        root.note = Tr.t("Opening %1…", FilePaths.baseName(p));
        imgProc.command = ["python3", root.drivesTool, "mount-image", p];
        imgProc.running = true;
    }
    Process {
        id: imgProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("That did not work") }; }
                if (r.paths && r.paths.length) {
                    root.imageMounted = r.paths[0];
                    root.note = "";
                    root.open(r.paths[0]);
                    root.loadDevices();
                } else {
                    root.note = "";
                    root.error = r.error || Tr.t("That did not work");
                }
            }
        }
    }
    function openUsb(mode, image) {
        root.usb = { mode: mode, image: image || "", drives: [], loading: true };
        root.usbError = "";
        usbList.running = true;
    }
    Process {
        id: usbList
        command: ["python3", root.drivesTool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let ds = [];
                try { ds = JSON.parse(text) || []; } catch (e) {}
                if (root.usb) root.usb = Object.assign({}, root.usb, { drives: ds, loading: false });
            }
        }
    }
    function usbWrite(d) {
        if (!root.usb || !d || root.usbBusy) return;
        root.usbDone = 0; root.usbTotal = 0; root.usbError = "";
        usbRun.command = ["python3", root.drivesTool, "write", root.usb.image, d.block];
        usbRun.what = Tr.t("%1 written to %2", FilePaths.baseName(root.usb.image), d.name);
        root.usbBusy = true;
        usbRun.running = true;
    }
    function usbFormat(d, fs, label, password) {
        if (!root.usb || !d || root.usbBusy) return;
        root.usbError = "";
        // the password goes on stdin, never on the command line (ps shows that)
        usbRun.secret = password || "";
        usbRun.command = ["python3", root.drivesTool, "format", d.block, fs, label || ""].concat(password ? ["--encrypt"] : []);
        usbRun.what = Tr.t("%1 formatted (%2)", d.name, fs);
        root.usbBusy = true;
        usbRun.running = true;
    }
    function usbStop() { if (usbRun.running) usbRun.signal(15); }
    function usbMode(m) { if (root.usb && !root.usbBusy) { root.usb = Object.assign({}, root.usb, { mode: m }); root.usbError = ""; } }
    // GNOME Disks' Create Disk Image: the whole drive into "<name> <date>.img" in the folder given
    function usbBackup(d, folder) {
        if (!root.usb || !d || root.usbBusy || !folder) return;
        root.usbDone = 0; root.usbTotal = 0; root.usbError = "";
        const out = folder + "/" + d.name.replace(/[\/]/g, "_") + " " + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".img";
        usbRun.command = ["python3", root.drivesTool, "backup", d.block, out];
        usbRun.what = Tr.t("%1 copied into %2", d.name, FilePaths.baseName(out));
        root.usbBusy = true;
        usbRun.running = true;
    }
    function usbPassphrase(d, oldPw, newPw) {
        if (!root.usb || !d || root.usbBusy || !newPw) return;
        root.usbError = "";
        usbRun.secret = JSON.stringify({ old: oldPw, new: newPw });
        usbRun.command = ["python3", root.drivesTool, "passphrase", d.block];
        usbRun.what = Tr.t("%1 has its new password", d.name);
        root.usbBusy = true;
        usbRun.running = true;
    }
    function driveHealth() { Quickshell.execDetached(["shani-cassini", "--section=smart"]); }
    Process {
        id: usbRun
        property string what: ""
        property string secret: ""
        property bool ok: false
        stdinEnabled: true
        onStarted: {
            ok = false;
            if (secret) { write(secret + "\n"); secret = ""; }
        }
        stdout: SplitParser {
            onRead: line => {
                let r;
                try { r = JSON.parse(line); } catch (e) { return; }
                if (r.total !== undefined) { root.usbTotal = r.total; root.usbDone = r.done; }
                if (r.error) root.usbError = r.error;
                if (r.ok) usbRun.ok = true;
            }
        }
        onExited: {
            root.usbBusy = false;
            if (usbRun.ok) {
                root.usbResult = usbRun.what;
                root.note = usbRun.what;
                root.usb = null;
                root.loadDevices();
            } else {
                if (!root.usbError) root.usbError = Tr.t("That did not work");
                root.usbResult = "error: " + root.usbError;
            }
        }
    }

    // the servers the network announces (files.py network: gvfs's network://)
    property var servers: []
    function loadServers() { run(["network"], r => { root.servers = r.servers || []; }); }
    // a server: the address typed (or picked from the ones used before); a login when it asks
    property bool connecting: false
    property string connectError: ""
    property bool connectNeedsLogin: false
    property var recentServers: Settings.data.filesRecentServers || []
    function connectServer(uri, user, password, domain) {
        if (!uri || root.connecting) return;
        root.connecting = true;
        root.connectError = "";
        connectProc.uri = uri.trim();
        connectProc.payload = JSON.stringify({ user: user || "", password: password || "", domain: domain || "" });
        connectProc.command = ["python3", root.tool, "connect", connectProc.uri];
        connectProc.stdinEnabled = true;
        connectProc.running = true;
    }
    Process {
        id: connectProc
        property string uri: ""
        property string payload: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() || Tr.t("could not connect") }; }
                root.connecting = false;
                root.connectError = r.error || "";
                root.connectNeedsLogin = !!r.needsLogin;
                if (r.path) {
                    const rs = [connectProc.uri].concat(root.recentServers.filter(x => x !== connectProc.uri)).slice(0, 8);
                    root.recentServers = rs;
                    Settings.data.filesRecentServers = rs;
                    root.open(r.path);
                    root.loadDevices();
                }
            }
        }
        onStarted: { write(payload + "\n"); stdinEnabled = false; }
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
