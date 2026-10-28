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
    // GTK reads this one switch for whether to keep a recent-files list at all
    Process {
        running: Settings.loaded
        command: ["gsettings", "set", "org.gnome.desktop.privacy", "remember-recent-files", String(root.d.rememberRecent)]
        onCommandChanged: if (Settings.loaded) running = true
    }
}
