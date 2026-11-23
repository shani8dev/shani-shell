pragma Singleton
// Tidying the person asked for (Settings > Privacy): trash older than N days
// emptied once a day — by when it was trashed (its .trashinfo), not when the
// file was made — and GTK's recent-files list switched off or cleared.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var d: Settings.data
    readonly property string trash: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash"
    property int emptied: 0               // items removed by the last tidy, for the tests

    // Scheduled-task transparency: what runs, how often, last attempt, and an
    // off switch per task. Read by IPC/settings; no UI in this file.
    readonly property var schedule: [
        ({ id: "trash", everyHours: 6 }),
        ({ id: "health", everyHours: 24 })
    ]
    property var disabled: ({})           // {"trash":true} or {"health":true}
    property real lastTrashRun: 0
    property real lastHealthRun: 0

    // Result of the last run, kept across runs (and visible to tests/IPC).
    property bool sweepFailed: false
    property string sweepError: ""
    property int sweepExitCode: 0
    property bool healthFailed: false
    property string healthError: ""
    property int healthRetries: 0
    property string _healthText: ""
    property string _sweepErr: ""

    function runTrashSweep() {
        if (d.trashDays <= 0 || root.disabled.trash)
            return;
        root.lastTrashRun = Date.now();
        emptyOldTrash();
    }
    function runHealthCheck() {
        if (root.disabled.health)
            return;
        root.lastHealthRun = Date.now();
        health.running = true;
    }

    function emptyOldTrash() {
        if (d.trashDays <= 0)
            return;
        // a line per item removed, counted after the pipe: a counter inside the
        // loop is the pipe's subshell's, and was always 0 to the shell
        // shortcut: a crafted ...trashinfo would otherwise resolve files/$b to
        // the whole Trash dir; skip empty and dot names before any rm -rf.
        sweep.command = ["bash", "-c", 't="$1"; d="$2"; find "$t/info" -name "*.trashinfo" -mtime +"$d" -print0 2>/dev/null | while IFS= read -r -d "" i; do
                b=${i##*/}; b=${b%.trashinfo}; [ -n "$b" ] && [ "$b" != "." ] && [ "$b" != ".." ] || continue; rm -rf "$t/files/$b" 2>/dev/null && rm -f "$i" 2>/dev/null && echo || echo "could not remove $b" >&2; done | wc -l', "bash", trash, String(d.trashDays - 1)];
        sweep.running = true;
    }
    function emptyTrash() { Quickshell.execDetached(["gio", "trash", "--empty"]); }
    function clearRecent() {
        Quickshell.execDetached(["sh", "-c", 'f="${XDG_DATA_HOME:-$HOME/.local/share}/recently-used.xbel"; [ -f "$f" ] && printf "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>\\n<xbel version=\\"1.0\\"/>\\n" > "$f"; true']);
    }

    Process {
        id: sweep
        stdout: StdioCollector { onStreamFinished: root.emptied = parseInt(text.trim()) || 0 }
        stderr: StdioCollector { onStreamFinished: root._sweepErr = text }
        // the wc pipeline always exits 0, so failed removals report via stderr
        onExited: code => {
            root.sweepExitCode = code;
            root.sweepError = root._sweepErr.trim();
            root.sweepFailed = code !== 0 || root.sweepError.length > 0;
        }
    }
    Timer {
        interval: 6 * 3600 * 1000
        running: root.d.trashDays > 0 && !root.disabled.trash
        repeat: true
        triggeredOnStart: true
        onTriggered: root.runTrashSweep()
    }

    // A disk that says it is failing (SMART, as UDisks reads it - no root
    // needed): told once a day, with the Disk health page one click away.
    // The details and the self-tests live in Disk health; this is only the warning.
    property var failing: []              // drive models, for the tests
    Process {
        id: health
        command: ["sh", "-c", 'gdbus call --system --dest org.freedesktop.UDisks2 --object-path /org/freedesktop/UDisks2 --method org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: root._healthText = text }
        onExited: code => {
            if (code !== 0) {
                // UDisks2 is often not up yet when the shell starts. Keep the
                // last known failing set instead of wiping it with a dead probe.
                root.healthFailed = true;
                root.healthError = "gdbus exited " + code;
                root.healthRetries = root.healthRetries + 1;
                if (root.healthRetries <= 3)
                    healthRetry.running = true;
                return;
            }
            root.healthFailed = false;
            root.healthError = "";
            root.healthRetries = 0;
            // per drive object: its Model, and SmartFailing (ATA) or a non-zero
            // SmartCriticalWarning list (NVMe)
            const out = [];
            for (const part of root._healthText.split(/objectpath '/).slice(1)) {
                const model = (/'Model': <'([^']*)'>/.exec(part) || [])[1];
                const ata = /'SmartFailing': <true>/.test(part);
                const nvme = /'SmartCriticalWarning': <\[('[^']+'[^\]]*)\]>/.test(part);
                if (model && (ata || nvme))
                    out.push(model);
            }
            root.failing = out;
            if (out.length)
                Quickshell.execDetached(["sh", "-c", 'a=$(notify-send -a Drives -u critical -i drive-harddisk -A open="$3" "$1" "$2"); [ "$a" = open ] && exec shani ipc call shani modelsOpen',
                    "sh", Tr.t("A disk may be failing"), Tr.t("%1 reports problems. Back up what matters now.", out.join(", ")), Tr.t("Disk health")]);
        }
    }
    Timer {
        id: healthRetry
        interval: 5 * 60 * 1000
        repeat: false
        onTriggered: root.runHealthCheck()
    }
    Timer {
        interval: 24 * 3600 * 1000
        running: !root.disabled.health
        repeat: true
        triggeredOnStart: true
        onTriggered: root.runHealthCheck()
    }
    // GTK reads this one switch for whether to keep a recent-files list at all
    Process {
        running: Settings.loaded
        command: ["gsettings", "set", "org.gnome.desktop.privacy", "remember-recent-files", String(root.d.rememberRecent)]
        onCommandChanged: if (Settings.loaded) running = true
    }
}
