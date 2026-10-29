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

    function emptyOldTrash() {
        if (d.trashDays <= 0)
            return;
        sweep.command = ["sh", "-c", 't="$1"; n=0; for i in $(find "$t/info" -name "*.trashinfo" -mtime +"$2" 2>/dev/null); do
                b=${i##*/}; b=${b%.trashinfo}; rm -rf "$t/files/$b" && rm -f "$i" && n=$((n + 1)); done; echo $n', "sh", trash, String(d.trashDays - 1)];
        sweep.running = true;
    }
    function emptyTrash() { Quickshell.execDetached(["gio", "trash", "--empty"]); }
    function clearRecent() {
        Quickshell.execDetached(["sh", "-c", 'f="${XDG_DATA_HOME:-$HOME/.local/share}/recently-used.xbel"; [ -f "$f" ] && printf "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>\\n<xbel version=\\"1.0\\"/>\\n" > "$f"; true']);
    }

    Process { id: sweep; stdout: StdioCollector { onStreamFinished: root.emptied = parseInt(text.trim()) || 0 } }
    Timer { interval: 6 * 3600 * 1000; running: root.d.trashDays > 0; repeat: true; triggeredOnStart: true; onTriggered: root.emptyOldTrash() }

    // A disk that says it is failing (SMART, as UDisks reads it - no root
    // needed): told once a day, with Cassini's Disk health page one click away.
    // The details and the self-tests are Cassini's; this is only the warning.
    property var failing: []              // drive models, for the tests
    Process {
        id: health
        command: ["sh", "-c", 'gdbus call --system --dest org.freedesktop.UDisks2 --object-path /org/freedesktop/UDisks2 --method org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                // per drive object: its Model, and SmartFailing (ATA) or a non-zero
                // SmartCriticalWarning list (NVMe)
                const out = [];
                for (const part of text.split(/objectpath '/).slice(1)) {
                    const model = (/'Model': <'([^']*)'>/.exec(part) || [])[1];
                    const ata = /'SmartFailing': <true>/.test(part);
                    const nvme = /'SmartCriticalWarning': <\[('[^']+'[^\]]*)\]>/.test(part);
                    if (model && (ata || nvme))
                        out.push(model);
                }
                root.failing = out;
                if (out.length)
                    Quickshell.execDetached(["sh", "-c", 'a=$(notify-send -a Drives -u critical -i drive-harddisk -A open="$3" "$1" "$2"); [ "$a" = open ] && exec shani-cassini --section=smart',
                        "sh", Tr.t("A disk may be failing"), Tr.t("%1 reports problems. Back up what matters now.", out.join(", ")), Tr.t("Disk health")]);
            }
        }
    }
    Timer { interval: 24 * 3600 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: health.running = true }
    // GTK reads this one switch for whether to keep a recent-files list at all
    Process {
        running: Settings.loaded
        command: ["gsettings", "set", "org.gnome.desktop.privacy", "remember-recent-files", String(root.d.rememberRecent)]
        onCommandChanged: if (Settings.loaded) running = true
    }
}
