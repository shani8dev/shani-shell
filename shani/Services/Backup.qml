pragma Singleton
// ShaniOS backups (shani-backup, after Time Machine): its schedule and where it
// writes, from its own GSettings, and "back up now" — a home backup to that
// location, the result told as a notification.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool available: false
    property bool scheduled: false
    property string time: ""
    property string location: ""
    property bool running: job.running
    readonly property string summary: !available ? "" : location === "" ? "Not set up"
        : (scheduled ? "Daily at " + time : "Off") + " · " + location

    function refresh() { if (available) read.running = true; }
    function backupNow() {
        if (location === "") {
            Quickshell.execDetached(["shani-cassini"]);
            return;
        }
        job.command = ["shani-backup", "backup", Quickshell.env("HOME"), "--destination", location, "--json"];
        job.running = true;
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v shani-backup"]
        onExited: code => { root.available = code === 0; root.refresh(); }
    }
    Process {
        id: read
        command: ["sh", "-c", "gsettings get org.shani.backup enable-scheduler; gsettings get org.shani.backup schedule-time; gsettings get org.shani.backup backup-location"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n").map(x => x.replace(/^'|'$/g, ""));
                root.scheduled = l[0] === "true";
                root.time = l[1] || "";
                root.location = l[2] || "";
            }
        }
    }
    Process {
        id: job
        onExited: code => Quickshell.execDetached(["notify-send", "-a", "Backup", "-i", "drive-harddisk",
            code === 0 ? "Backup finished" : "Backup failed", code === 0 ? "Your home folder is in " + root.location : "See Cassini's Backup page"])
    }
    Timer { interval: 300000; running: root.available; repeat: true; onTriggered: root.refresh() }
}
