pragma Singleton
// Notification filtering rules (noctalia-inspired): regex/glob/substring
// patterns that match notification content (app name, summary, body) and
// return actions: mute, hide, block, silence. Stored in settings.json under
// Settings.data.notifRules.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property var rules: []

    readonly property string configPath: Quickshell.env("HOME") + "/.config/shani-shell/notif-rules.json"

    FileView {
        id: rulesFile
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(rulesFile.text() || "{}");
                root.rules = Array.isArray(parsed.rules) ? parsed.rules.filter(r => (r.pattern || "").trim() !== "") : [];
            } catch (e) { root.rules = []; }
        }
        onLoadFailed: root.rules = []
    }

    function save() {
        Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.config/shani-shell"]);
        root.rules = root.rules.filter(r => (r.pattern || "").trim() !== "");
        const text = JSON.stringify({ rules: root.rules });
        Quickshell.execDetached(["sh", "-c", "cat > '" + root.configPath + "' << 'EOF'\n" + text + "\nEOF"]);
    }

    // Evaluate a notification against rules; return action string or empty
    function evaluate(appName, summary, body) {
        const haystack = [appName || "", summary || "", body || ""].join(" ");
        for (let i = 0; i < root.rules.length; i++) {
            const r = root.rules[i];
            const pattern = (r.pattern || "").trim();
            if (pattern === "") continue;
            let matched = false;
            // Regex: wrapped in /.../
            if (pattern.length >= 3 && pattern.startsWith("/") && pattern.endsWith("/")) {
                try { matched = new RegExp(pattern.slice(1, -1)).test(haystack); } catch (e) {}
            }
            // Glob: contains *
            else if (pattern.indexOf("*") >= 0) {
                try {
                    const reStr = pattern.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
                    matched = new RegExp(reStr, "i").test(haystack);
                } catch (e) {
                    matched = haystack.toLowerCase().indexOf(pattern.toLowerCase()) >= 0;
                }
            }
            // Plain substring
            else {
                matched = haystack.toLowerCase().indexOf(pattern.toLowerCase()) >= 0;
            }
            if (matched) {
                const a = (r.action || "block").toLowerCase();
                if (a === "mute" || a === "hide") return "hide";
                if (a === "silence") return "hide";
                return a;  // "block" or custom
            }
        }
        return "";  // no match: allow notification
    }

    Component.onCompleted: rulesFile.reload()
}
