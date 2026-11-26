pragma Singleton
// The backup tool (shani-backup), as the shell shows it. Every answer and every action goes
// through bridge/backup.py, which runs shani-backup's own commands:
//   list / home-list / snapshot-list  - what is there
//   backup / restore                 - the copy on the other drive
//   snapshot-create/delete           - btrfs snapshots on this disk
//   home-snapshot / home-remove      - snapshots of a home
//   schedule                         - the daily backup's switch and time
// The service holds data and codes; the panels own the words.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/Format.js" as Format
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_BACKUP_BRIDGE"), "backup.py")
    readonly property string commandTool: Quickshell.env("SHANI_BACKUP_TOOL") || "shani-backup"
    readonly property string filesTool: ToolPath.of(Quickshell.env("SHANI_FILES_TOOL"), "files.py")
    readonly property string homeTool: Quickshell.env("SHANI_BACKUP_SNAPSHOT_PATH") || "/home/.snapshots"
    property bool available: false
    property bool loading: false
    property bool running: backupJob.running
    property string busyOp: ""
    property string note: ""
    property string error: ""
    property int progress: 0
    property int peakProgress: 0
    property string progressFile: ""
    property var backupResult: null

    // what shani-backup answered
    property bool driveSetUp: false
    property bool reachable: false
    property string repository: ""
    property bool scheduleOn: false
    property string scheduleTime: ""
    property var backups: []
    property var restoreTest: null
    property var snapshots: []          // snapshots of this person's home (home list)
    property var btrfsSnapshots: []      // btrfs snapshots under homeTool
    property string versions: ""
    property string drive: ""
    property bool stale: false         // newest backup is at least three days old
    property string newest: ""
    property bool timerKnown: false    // the daily snapshot timer for this user
    property bool timerEnabled: false
    property bool timerActive: false
    property string timerNext: ""
    property bool diskKnown: false
    property real diskTotal: 0
    property real diskFree: 0
    property real diskUsed: 0
    property bool diskLow: false
    property var findResults: []
    property bool findSearched: false
    property bool findTruncated: false
    property string findPick: ""

    // what the person picked / the shell did last
    property string tab: "home"
    property string restorePick: ""      // backup id chosen in the restore form
    property string restoreTarget: ""
    property string lastAction: ""
    property string lastPath: ""
    property string lastTarget: ""
    property bool copyBusy: false

    readonly property string summary: drive

    function refresh() {
        if (!available) return;
        error = "";
        loading = true;
        list.running = true;
        homeList.running = true;
        snapshotList.running = true;
        timerState.running = true;
        diskUsage.running = true;
    }

    // Open the shell's own Backup window at a tab. The GTK app is never started.
    function open(page) {
        tab = page || "home";
        Ui.closeAll();
        Ui.backup = true;
    }

    function formatBytes(n) { return Format.humanSize(n || 0, "whole"); }

    function day(stamp) {
        const m = /(\d{4}-\d\d-\d\d)/.exec(stamp || "");
        if (!m) return stamp || "";
        const d = new Date(m[1] + "T00:00:00"), t = new Date(); t.setHours(0, 0, 0, 0);
        const n = Math.round((t - d) / 86400000);
        return n === 0 ? Tr.t("today") : n === 1 ? Tr.t("yesterday") : Qt.formatDate(d, "d MMM");
    }

    // One honest line for the daily copy switch: why it is off, and when it
    // runs next. The words are ours; enabled/active/next come from the timer.
    function timerHint() {
        if (!timerKnown) return Tr.t("A copy of your home is kept on this disk every day.");
        if (!timerEnabled) return Tr.t("Off. Turn it on to keep a daily copy of your home on this disk.");
        if (!timerActive) return Tr.t("On, but not running now. It starts again at the next sign-in.");
        return timerNext !== "" ? Tr.t("On. Next copy: %1", timerNext)
            : Tr.t("On. The next copy time is not known yet.");
    }

    function diskPercent() {
        return diskTotal > 0 ? Math.round(100 * (diskTotal - diskFree) / diskTotal) : 0;
    }

    function openPath(path) {
        if (!path) return;
        Files.show(path);
    }

    // ---- reads ----------------------------------------------------------------
    Process {
        running: true
        command: ["sh", "-c", 'command -v "$0" >/dev/null 2>&1', root.commandTool]
        onExited: code => { root.available = code === 0; root.refresh(); }
    }

    Process {
        id: list
        command: [root.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                let d = {};
                try { d = JSON.parse(text.trim().split("\n").pop() || "{}"); } catch (e) {}
                if (d.error && d.ok === false) root.error = d.error;
                root.repository = d.repository || "";
                root.reachable = !!d.reachable;
                root.driveSetUp = !!(d.repository && d.set_up);
                root.scheduleOn = !!(d.schedule && d.schedule.on);
                root.scheduleTime = (d.schedule && d.schedule.time) || "";
                root.backups = d.ok !== false && Array.isArray(d.backups) ? d.backups : [];
                root.restoreTest = d.restore_test || null;
                root.stale = d.ok !== false && !!d.stale;
                root.newest = d.newest || "";
                root.drive = !root.repository ? Tr.t("No backup drive chosen yet")
                    : !root.reachable ? Tr.t("The backup drive is not connected")
                    : !root.driveSetUp ? Tr.t("This folder is not set up for backups yet")
                    : !d.ok ? (d.error || Tr.t("The backup tool did not answer"))
                    : Tr.t("Last %1", root.backups.length ? root.day(root.backups[0].time) + " " + String(root.backups[0].time).slice(11, 16) : Tr.t("never"))
                      + " · " + (root.scheduleOn ? Tr.t("every day at %1", root.scheduleTime) : Tr.t("by hand"));
            }
        }
    }

    Process {
        id: homeList
        command: [root.tool, "home-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                let d = {};
                try { d = JSON.parse(text.trim().split("\n").pop() || "{}"); } catch (e) {}
                const items = d.ok !== false && Array.isArray(d.snapshots) ? d.snapshots : [];
                root.snapshots = items.map(s => ({
                    name: s.name || "", path: s.path || "", whole: !!s.whole,
                    displayDate: root.day(s.name),
                    subtitle: String(s.name || "").startsWith("manual-") ? Tr.t("Taken by hand")
                        : String(s.name || "").startsWith("predeploy-") ? Tr.t("Before an update") : Tr.t("Daily")
                }));
                root.versions = d.ok === false ? (d.error || Tr.t("The backup tool did not answer"))
                    : items.length === 0 ? Tr.t("No snapshots yet — your home is snapshotted once a day")
                    : Tr.t("%1 on this disk · latest %2",
                           items.length === 1 ? Tr.t("1 snapshot") : Tr.t("%1 snapshots", items.length),
                           root.day(items[0].name));
            }
        }
    }

    Process {
        id: snapshotList
        command: [root.tool, "snapshot-list", root.homeTool]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text.trim().split("\n").pop() || "{}"); } catch (e) {}
                const paths = d.ok !== false && Array.isArray(d.snapshots) ? d.snapshots : [];
                root.btrfsSnapshots = paths.map(p => ({ path: p, name: String(p).split("/").pop() || p }));
            }
        }
    }

    // The daily snapshot timer is a user unit: no administrator rights needed.
    Process {
        id: timerState
        command: [root.tool, "home-timer", "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text.trim().split("\n").pop() || "{}"); } catch (e) {}
                root.timerKnown = d.ok !== false;
                if (root.timerKnown) {
                    root.timerEnabled = !!d.enabled;
                    root.timerActive = !!d.active;
                    root.timerNext = d.next || "";
                }
            }
        }
    }

    Process {
        id: diskUsage
        command: [root.tool, "disk-usage", root.homeTool]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text.trim().split("\n").pop() || "{}"); } catch (e) {}
                root.diskKnown = d.ok !== false;
                if (root.diskKnown) {
                    root.diskTotal = d.total || 0;
                    root.diskFree = d.free || 0;
                    root.diskUsed = d.used || 0;
                    root.diskLow = !!d.low;
                }
            }
        }
    }

    // ---- back up now, with the command's own progress ---------------------------
    Process {
        id: backupJob
        stdout: SplitParser {
            onRead: line => {
                const l = String(line).trim();
                if (!l) return;
                let d;
                try { d = JSON.parse(l); } catch (e) { return; }
                if (d.progress !== undefined) {
                    root.progress = d.progress;
                    if (d.progress > root.peakProgress) root.peakProgress = d.progress;
                    root.progressFile = d.file || "";
                } else if (d.ok !== undefined || d.error) {
                    root.backupResult = d;
                }
            }
        }
        stderr: StdioCollector { id: backupErr }
        onExited: code => {
            const d = root.backupResult || {};
            const ok = code === 0 && d.ok !== false;
            root.busyOp = "";
            root.progress = 0;
            root.progressFile = "";
            root.backupResult = null;
            root.lastAction = "backup";
            root.note = ok ? Tr.t("Your home folder is on the backup drive") : "";
            root.error = ok ? "" : (d.error || backupErr.text.trim().split("\n").pop()
                || Tr.t("The backup did not finish. Is the drive connected?"));
            if (ok) root.refresh();
        }
    }

    function backupNow() {
        if (backupJob.running || !root.available) return;
        if (!root.driveSetUp) { root.error = Tr.t("Choose a backup drive first"); return; }
        root.error = "";
        root.note = Tr.t("Backing up your home…");
        root.progress = 0;
        root.peakProgress = 0;
        root.busyOp = "backup";
        backupJob.command = [root.tool, "backup"];
        backupJob.running = false;
        backupJob.running = true;
    }

    // ---- one action at a time: every other flow goes through this Process ------
    property string pendingOp: ""
    property string pendingNote: ""
    Process {
        id: action
        stdout: StdioCollector { id: actionOut }
        stderr: StdioCollector { id: actionErr }
        onExited: code => {
            let d = {};
            try { d = JSON.parse(actionOut.text.trim().split("\n").pop() || "{}"); } catch (e) {}
            const op = root.pendingOp;
            const ok = code === 0 && d.ok !== false;
            root.busyOp = "";
            root.lastAction = op;
            if (d.path) root.lastPath = d.path;
            if (ok) {
                root.note = root.pendingNote;
                root.error = "";
            } else {
                root.note = "";
                root.error = code === 126 || code === 127 ? Tr.t("Administrator rights were not given")
                    : (d.error || actionErr.text.trim().split("\n").pop() || Tr.t("That did not work"));
            }
            if (op === "find-file") {
                root.findSearched = true;
                root.findResults = Array.isArray(d.results) ? d.results : [];
                root.findTruncated = !!d.truncated;
                root.findPick = "";
            }
            if (op === "home-snapshot" || op === "home-remove" || op === "snapshot-create"
                || op === "snapshot-delete" || op === "schedule" || op === "restore"
                || op === "home-timer") root.refresh();
        }
    }

    // note: what to say once the step has worked (the panel shows its own
    // progress line while it runs)
    function runOp(op, args, note) {
        if (action.running || backupJob.running) return false;
        root.pendingOp = op;
        root.pendingNote = note || "";
        root.busyOp = op;
        root.error = "";
        root.note = "";
        action.command = [root.tool, op].concat(args);
        action.running = false;
        action.running = true;
        return true;
    }

    function restoreTo(snapshot, target) {
        if (!snapshot || !target) { root.error = Tr.t("Choose a backup and a folder first"); return false; }
        root.restorePick = snapshot;
        root.restoreTarget = target;
        root.lastTarget = target;
        return runOp("restore", [target, snapshot], Tr.t("Restored into %1", target));
    }

    function snapshotCreate(source, destination, readonly) {
        return runOp("snapshot-create", readonly ? [source, destination, "--readonly"] : [source, destination],
                     Tr.t("Snapshot taken"));
    }

    function snapshotDelete(path) { return runOp("snapshot-delete", [path], Tr.t("Snapshot removed")); }
    function homeSnapshotNow() { return runOp("home-snapshot", [], Tr.t("Snapshot of your home taken")); }
    function homeRemove(name) { return runOp("home-remove", [name], Tr.t("Snapshot removed")); }
    function setSchedule(on) { return runOp("schedule", [on ? "on" : "off"], on ? Tr.t("Daily backup turned on") : Tr.t("Daily backup turned off")); }
    function setScheduleTime(hhmm) { return runOp("schedule", ["at", hhmm], Tr.t("Daily backup at %1", hhmm)); }
    function setHomeTimer(on) { return runOp("home-timer", [on ? "on" : "off"], on ? Tr.t("Daily copy turned on") : Tr.t("Daily copy turned off")); }
    function findFile(name) {
        root.findSearched = false;
        root.findResults = [];
        root.findPick = "";
        return runOp("find-file", [name], "");
    }

    // Restore a file or folder from a home snapshot with the shell's own copy
    // engine (bridge/files.py paste): never over another file.
    Process {
        id: copyJob
        stdout: StdioCollector { id: copyOut }
        stderr: StdioCollector { id: copyErr }
        onExited: code => {
            root.copyBusy = false;
            let d = {};
            try { d = JSON.parse(copyOut.text.trim().split("\n").pop() || "{}"); } catch (e) {}
            root.lastAction = "copy-from-snapshot";
            if (code === 0 && d.ok !== false) {
                root.note = Tr.t("Restored into %1", d.dest || root.lastTarget);
                root.error = "";
            } else {
                root.note = "";
                root.error = d.error || copyErr.text.trim().split("\n").pop() || Tr.t("That file could not be restored");
            }
        }
    }
    function restoreFromHome(source, dest) {
        if (!source || !dest) { root.error = Tr.t("Pick a file and a place to put it first"); return false; }
        root.lastTarget = dest;
        root.copyBusy = true;
        root.error = "";
        root.note = "";
        copyJob.command = [root.filesTool, "paste", dest, "copy", source];
        copyJob.running = false;
        copyJob.running = true;
        return true;
    }

    Connections { target: Ui; function onControlCenterChanged() { if (Ui.controlCenter) root.refresh(); } }
}
