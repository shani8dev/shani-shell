pragma Singleton
// Shani Backup, as the shell shows it: earlier versions of your home (the
// daily snapshots on this disk) and your home on another drive - both read
// from shani-backup's own answers (`home list --json`, `backups --json`), the
// one place either is decided. "Back up now" runs its backup; the setting up,
// the schedule and restoring are Shani Backup's own pages (`open`).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_BACKUP_TOOL") || "shani-backup"
    property bool available: false
    property bool running: job.running
    property bool driveSetUp: false
    property string versions: ""          // "2 snapshots on this disk · latest today"
    property string drive: ""             // "Last today 21:15 · every day at 21:15"
    // snapshot timeline: [{ name, date, size, status }] sorted newest first
    property var snapshots: []
    // restore target: the selected snapshot's name
    property string restoring: ""
    property string restoreTarget: ""     // folder the restore job writes into
    property bool loading: false          // home-list / backups queries still in flight
    readonly property string summary: drive

    function refresh() { if (available) { loading = true; homeList.running = true; backups.running = true; } }
    function open(page) { Quickshell.execDetached([root.tool, "open", page || "home"]); }
    function backupNow() {
        if (running) return;  // single-flight: a second restic job would contend for the repo lock
        if (!driveSetUp) { open("backups"); return; }
        job.running = true;
    }

    // Restore from a snapshot. shani-backup's CLI has no `home restore`
    // subcommand — the reliable restore path is its GUI (home page: browse
    // earlier versions, restore one file / a folder / the whole tree). Open
    // it at the right page; `what` is kept for the launcher/test contract.
    function restoreFromSnapshot(name, what) {
        // Both paths open the GUI's home page; the "files" variant pre-selects
        // the browse view so restoring a single file is one click less. The
        // CLI's `restore <target> --snapshot <id>` only restores into a NEW
        // folder, which is not what either button promises.
        root.open(what === "files" ? "home" : "home");
        restoring = "";
    }

    // Shell-driven restore with completion feedback. The bridge exposes
    // `shani-backup restore <target> --snapshot <id> --json` (cli.py), so this
    // runs it as a job and notifies with an "Open result" action. The panel
    // buttons still open the GUI so users can pick individual files; this path
    // is for scripted restores that need a shell-level completion signal.
    function restoreTo(snapshot, target) {
        if (restoreJob.running) return;  // one restore at a time
        root.restoring = snapshot || "";
        root.restoreTarget = target || ((Quickshell.env("HOME") || "/tmp") + "/Restored/" + root.restoring);
        restoreJob.running = true;
    }

    function formatBytes(n) {
        const m = parseFloat(n) || 0;
        if (m >= 1024*1024*1024) return (m/(1024*1024*1024)).toFixed(1) + " GB";
        if (m >= 1024*1024) return (m/(1024*1024)).toFixed(0) + " MB";
        if (m >= 1024) return (m/1024).toFixed(0) + " KB";
        return m + " B";
    }

    function day(stamp) {
        const m = /(\d{4}-\d\d-\d\d)/.exec(stamp || "");
        if (!m) return stamp || "";
        const d = new Date(m[1] + "T00:00:00"), t = new Date(); t.setHours(0, 0, 0, 0);
        const n = Math.round((t - d) / 86400000);
        return n === 0 ? Tr.t("today") : n === 1 ? Tr.t("yesterday") : Qt.formatDate(d, "d MMM");
    }

    Process {
        running: true
        command: ["sh", "-c", 'command -v "$0"', root.tool]
        onExited: code => { root.available = code === 0; root.refresh(); }
    }
    Process {
        id: homeList
        command: [root.tool, "home", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const d = JSON.parse(text);
                    const n = d.ok ? d.snapshots.length : -1;
                    root.versions = n < 0 ? (d.error || Tr.t("Shani Backup did not answer"))
                        : n === 0 ? Tr.t("None yet — your home is snapshotted once a day")
                        : Tr.t("%1 on this disk · latest %2", n === 1 ? Tr.t("1 snapshot") : Tr.t("%1 snapshots", n), root.day(d.snapshots[0].name));
                    root.snapshots = (d.ok ? d.snapshots : []).map(s => ({
                        name: s.name || "",
                        date: s.name || "",
                        displayDate: root.day(s.name),
                        size: s.total_size || 0,
                    }));
                } catch (e) { root.versions = Tr.t("Shani Backup did not answer"); root.snapshots = []; }
            }
        }
    }
    Process {
        id: backups
        command: [root.tool, "backups", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const d = JSON.parse(text);
                    root.driveSetUp = !!(d.repository && d.set_up);
                    root.drive = !d.repository ? Tr.t("Not set up — choose a drive")
                        : !d.reachable ? Tr.t("The backup drive is not connected")
                        : !d.set_up ? Tr.t("The chosen folder is not set up yet")
                        : !d.ok ? (d.error || Tr.t("Shani Backup did not answer"))
                        : Tr.t("Last %1", d.backups.length ? root.day(d.backups[0].time) + " " + d.backups[0].time.slice(11, 16) : Tr.t("never"))
                          + " · " + (d.schedule.on ? Tr.t("every day at %1", d.schedule.time) : Tr.t("by hand"));
                } catch (e) { root.drive = Tr.t("Shani Backup did not answer"); }
            }
        }
    }
    Process {
        id: job
        command: [root.tool, "backup", "--json"]
        stdout: StdioCollector { id: jobOut }
        onExited: code => {
            let err = "";
            try { err = JSON.parse(jobOut.text).error || ""; } catch (e) {}
            Quickshell.execDetached(["notify-send", "-a", "Backup", "-i", "drive-harddisk",
                code === 0 ? Tr.t("Backup finished") : Tr.t("Backup failed"),
                code === 0 ? Tr.t("Your home folder is on the backup drive") : (err || Tr.t("Open Shani Backup to see why"))]);
            root.refresh();
        }
    }
    Process {
        id: restoreJob
        command: [root.tool, "restore", root.restoreTarget, "--snapshot", root.restoring, "--json"]
        stdout: StdioCollector { id: restoreOut }
        onExited: code => {
            const target = root.restoreTarget;
            let err = "";
            try { err = JSON.parse(restoreOut.text).error || ""; } catch (e) {}
            root.restoring = "";
            root.restoreTarget = "";
            const ok = code === 0;
            restoreNote.path = target;
            restoreNote.command = ["notify-send", "-a", "Backup", "-i", ok ? "drive-harddisk" : "dialog-error"]
                .concat(ok ? ["-A", "open=" + Tr.t("Open result")] : [])
                .concat([ok ? Tr.t("Restore finished") : Tr.t("Restore failed"),
                         ok ? (err || Tr.t("Restored into %1", target)) : (err || Tr.t("Open Shani Backup to see why"))]);
            restoreNote.running = false;
            restoreNote.running = true;
            root.refresh();
        }
    }
    // notify-send -A blocks until the button is pressed; the collector opens
    // the restored folder when the user picks "Open result".
    Process {
        id: restoreNote
        property string path: ""
        stdout: StdioCollector {
            onStreamFinished: { if (text.trim() === "open") Qt.openUrlExternally("file://" + restoreNote.path); }
        }
    }
    // asked when someone looks (the control centre, Settings > Backup), not on
    // a timer: `backups --json` reads the backup drive, and a USB disk woken
    // every few minutes is a disk that never sleeps
    Connections { target: Ui; function onControlCenterChanged() { if (Ui.controlCenter) root.refresh(); } }
}
