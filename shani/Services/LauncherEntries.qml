pragma Singleton
// Apps' own counts and progress for their dock icons (the LauncherEntry API:
// Telegram's unread count, a download's progress), from bridge/launcher-entry.py,
// which waits on the session bus. Keyed by lower-case desktop id.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_LAUNCHER_ENTRY_TOOL") || "/usr/lib/shani-shell/launcher-entry.py"
    property var entries: ({})            // id -> { count, countVisible, progress, progressVisible, urgent }
    property bool ready: false

    function of(entry, id) {
        const keys = [id, entry && entry.id].filter(Boolean).map(k => k.toLowerCase());
        for (const k of keys)
            if (entries[k]) return entries[k];
        return null;
    }

    Process {
        id: bridge
        running: true
        command: [root.tool]
        stdout: SplitParser {
            onRead: line => {
                let d;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (d.ready) { root.ready = true; return; }
                const k = (d.app || "").toLowerCase();
                if (!k) return;
                const m = Object.assign({}, root.entries);
                m[k] = Object.assign({}, m[k] || {}, d);
                root.entries = m;
            }
        }
        // gone (the bus restarted): once more, a little later
        onExited: retry.start()
    }
    Timer { id: retry; interval: 5000; onTriggered: bridge.running = true }
}
