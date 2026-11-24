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

    // Queries the person actually submitted, newest first (after Spotlight's
    // "Recent searches"). Kept in this state service so the launcher itself
    // stays a view and the rules live in one testable place.
    property var searchHistory: []        // strings, newest first

    readonly property var operators: [
        { id: "app", hint: "app:firefox" },
        { id: "file", hint: "file:report" },
        { id: "web", hint: "web:weather" },
        { id: "clip", hint: "clip:meeting" },
        { id: "action", hint: "action:dark" }
    ]
    // A leading word + colon is an operator only when that word is one of ours:
    // URLs, paths and the existing ":" emoji mode keep their usual meaning.
    function parseQuery(raw) {
        const s = String(raw || "");
        const m = /^\s*([a-zA-Z]+)\s*:\s*([\s\S]*)$/.exec(s);
        const id = m ? m[1].toLowerCase() : "";
        const text = (m ? m[2] : s).trim();
        if (id && operators.some(o => o.id === id))
            return { op: id, text: text, active: true, empty: text === "" };
        return { op: "", text: s.trim(), active: false, empty: s.trim() === "" };
    }

    function remember(raw) {
        const t = String(raw || "").trim();
        if (t.length < 2 || parseQuery(t).active || root.searchHistory[0] === t) return;
        const h = [t].concat(root.searchHistory.filter(x => x !== t)).slice(0, 12);
        root.searchHistory = h;
        history.setText(JSON.stringify(h));
    }
    function forget(raw) {
        const t = String(raw || "");
        const h = root.searchHistory.filter(x => x !== t);
        if (h.length === root.searchHistory.length) return;
        root.searchHistory = h;
        history.setText(JSON.stringify(h));
    }
    function clearHistory() {
        root.searchHistory = [];
        history.setText("[]");
    }
    // A missing or corrupt file means no history, never a broken launcher.
    FileView {
        id: history
        path: Quickshell.statePath("launcher-history.json")
        printErrors: false
        onLoaded: {
            try {
                const v = JSON.parse(text());
                root.searchHistory = Array.isArray(v) ? v.filter(x => typeof x === "string").slice(0, 12) : [];
            } catch (e) { root.searchHistory = []; }
        }
    }

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
                if (!d || typeof d !== "object") return;   // "null" would throw on d.ready
                if (d.ready) { root.ready = true; return; }
                const k = String(d.app || "").toLowerCase();
                if (!k) return;
                const m = Object.assign({}, root.entries);
                const e = Object.assign({}, m[k] || {});
                for (const f of ["count", "countVisible", "progress", "progressVisible", "urgent"])
                    if (d[f] !== undefined) e[f] = d[f];
                m[k] = e;
                root.entries = m;
            }
        }
        // gone (the bus restarted): drop the old counts rather than leave them
        // on the dock as if they were live, then try once more, a little later
        onExited: {
            root.ready = false;
            root.entries = {};
            retry.start()
        }
    }
    Timer { id: retry; interval: 5000; onTriggered: bridge.running = true }
}
