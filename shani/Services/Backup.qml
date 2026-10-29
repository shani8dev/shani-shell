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
    readonly property string summary: drive

    function refresh() { if (available) { homeList.running = true; backups.running = true; } }
    function open(page) { Quickshell.execDetached([root.tool, "open", page || "home"]); }
    function backupNow() {
        if (!driveSetUp) { open("backups"); return; }
        job.running = true;
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
                try {
                    const d = JSON.parse(text);
                    const n = d.ok ? d.snapshots.length : -1;
                    root.versions = n < 0 ? (d.error || Tr.t("Shani Backup did not answer"))
                        : n === 0 ? Tr.t("None yet — your home is snapshotted once a day")
                        : Tr.t("%1 on this disk · latest %2", n === 1 ? Tr.t("1 snapshot") : Tr.t("%1 snapshots", n), root.day(d.snapshots[0].name));
                } catch (e) { root.versions = Tr.t("Shani Backup did not answer"); }
            }
        }
    }
    Process {
        id: backups
        command: [root.tool, "backups", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
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
    // asked when someone looks (the control centre, Settings > Backup), not on
    // a timer: `backups --json` reads the backup drive, and a USB disk woken
    // every few minutes is a disk that never sleeps
    Connections { target: Ui; function onControlCenterChanged() { if (Ui.controlCenter) root.refresh(); } }
}
