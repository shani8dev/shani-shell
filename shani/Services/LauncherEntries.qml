pragma Singleton
// Apps' own counts and progress for their dock icons (the LauncherEntry API:
// Telegram's unread count, a download's progress), from bridge/launcher-entry.py,
// which waits on the session bus. Keyed by lower-case desktop id.
import Quickshell
import Quickshell.Io
import QtQuick
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_LAUNCHER_ENTRY_TOOL"), "launcher-entry.py")
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
        { id: "action", hint: "action:dark" },
        { id: "tool", hint: "tool:dictionary" }
    ]
    // Settings categories the launcher could not reach by name: the sidebar's
    // category id, its label and the words people actually type. Kept in the
    // service (not in Settings/*) so every search surface can use one list.
    readonly property var settingsLinks: [
        { id: "search", label: "Search", words: "search launcher files folders documents web engine google duckduckgo calculator nav hints", icon: "system-search" },
        { id: "printers", label: "Printers", words: "printers printer print cups default test page queue scanner add", icon: "printer" },
        { id: "sharing", label: "Sharing", words: "sharing share folder network samba smb files public remote nearby localsend airdrop send to phone visible", icon: "folder-remote" },
        { id: "firewall", label: "Firewall", words: "firewall ports services zones open block allow deny firewalld incoming connections", icon: "security-high" },
        { id: "backup", label: "Backup", words: "backup backups restore earlier versions snapshots time machine history deleted files drive restic", icon: "drive-harddisk" },
        { id: "boot", label: "Boot & Recovery", words: "boot recovery slot blue green rollback candidate boot failure A B", icon: "system-reboot" },
        { id: "updates", label: "Updates", words: "updates update upgrade channel stable latest rollback firmware fwupd restart reboot version", icon: "software-update-available" },
        { id: "automations", label: "Automations", words: "automations rules when then routines triggers wifi plugged headphones schedule shortcuts", icon: "system-run" },
        { id: "security", label: "Security", words: "security lsm apparmor audit password policy pwquality secure boot encryption kernel lockdown", icon: "security-high" },
        { id: "journal", label: "Journal", words: "journal logs journald vacuum storage systemd log rotate retention", icon: "document-open-recent" },
        { id: "chronoa", label: "Chronoa", words: "chronoa assistant ai island model voice wake word", icon: "face-smile-big" },
        { id: "storage", label: "Storage", words: "storage disk space free clean up cleanup trash cache thumbnails downloads flatpak", icon: "drive-harddisk" },
        { id: "screentime", label: "Screen time", words: "screen time wellbeing digital break reminder limit usage apps today week focus", icon: "preferences-desktop-screensaver" },
        { id: "modules", label: "Kernel modules", words: "kernel modules drivers loaded modprobe lsmod dependencies parameters", icon: "application-x-addon" }
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
