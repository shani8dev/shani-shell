pragma Singleton
// Release notes in the shell: the shipped whats-new.md is read and parsed here
// so Settings > About can show it without handing the file to xdg-open.
// SHANI_RELEASE_NOTES_FILE points at a repo copy; every path is checked and
// passed as an argument, never as shell script text.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool loaded: false
    property bool failed: false
    property string text: ""

    // External input: absolute, plain paths only. No traversal, whitespace or
    // shell metacharacters — the value becomes one quoted argument below.
    function safeNotesPath(value) {
        const p = String(value || "").trim();
        if (!p || p.charAt(0) !== "/" || p.indexOf("..") >= 0)
            return "";
        return /[\s$`;&|'"\\<>]/.test(p) ? "" : p;
    }

    // Inline Markdown to plain text: enough to read a shipped note, and no
    // way for a file to inject rich text into a Text element.
    function plainText(value) {
        return String(value || "")
            .replace(/\*\*([^*]+)\*\*/g, "$1")
            .replace(/\*([^*]+)\*/g, "$1")
            .replace(/`([^`]+)`/g, "$1")
            .replace(/\[\[([^\[\]]+)\]\]/g, "$1")
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, "$1")
            .replace(/<[^>]*>/g, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    // Markdown → rows the UI lays out: a heading per # line, a bullet per -/+
    // line (with its indented continuation joined on), a paragraph otherwise.
    function parseRows(md) {
        const rows = [];
        String(md || "").split(/\r?\n/).forEach(raw => {
            const line = raw.trim();
            if (!line) return;
            const heading = /^(#{1,6})\s+(.*)$/.exec(line);
            if (heading) {
                rows.push({ kind: "heading", level: heading[1].length, text: plainText(heading[2]) });
                return;
            }
            const bullet = /^[-*+]\s+(.*)$/.exec(line);
            if (bullet) {
                rows.push({ kind: "bullet", text: plainText(bullet[1]) });
                return;
            }
            const last = rows.length ? rows[rows.length - 1] : null;
            if (last && last.kind !== "heading" && /^\s+\S/.test(raw))
                // re-run plainText: a **bold span** can straddle the wrap
                last.text = plainText(last.text + " " + line);
            else
                rows.push({ kind: "para", text: plainText(line) });
        });
        return rows.filter(row => row.text !== "");
    }

    // One file may hold several versions: split on version headings so the UI
    // shows the newest first and discloses the older ones. An undated file is
    // one section, so no disclosure is offered for it.
    function splitVersions(md) {
        const version = /^\s*#{1,6}\s+(?:version\s+|v)?\d+(?:\.\d+)+/i;
        const parts = [];
        let current = null;
        String(md || "").split(/\r?\n/).forEach(line => {
            if (version.test(line)) {
                current = { label: plainText(line.replace(/^#{1,6}\s+/, "")), md: "" };
                parts.push(current);
            } else {
                if (!current) { current = { label: "", md: "" }; parts.push(current); }
                current.md += line + "\n";
            }
        });
        return parts.filter(part => part.md.trim() !== "");
    }

    readonly property string configuredPath: safeNotesPath(Quickshell.env("SHANI_RELEASE_NOTES_FILE") || "")
    readonly property var candidatePaths: {
        const paths = [];
        if (root.configuredPath) paths.push(root.configuredPath);
        paths.push("/usr/share/shani/whats-new.md");
        const home = Quickshell.env("HOME") || "";
        if (home) paths.push(home + "/Documents/shani/shani-shell/data/whats-new.md");
        paths.push("/work/data/whats-new.md");
        return paths;
    }

    function reload() { readProc.running = false; readProc.running = true; }

    Process {
        id: readProc
        // $0 is "sh"; every candidate stays a quoted item in "$@".
        command: ["sh", "-c", 'for f in "$@"; do [ -r "$f" ] && { cat -- "$f"; exit 0; }; done; exit 1', "sh"].concat(root.candidatePaths)
        stdout: StdioCollector { id: notesOut }
        onExited: code => {
            root.text = code === 0 ? notesOut.text : "";
            root.failed = code !== 0;
            root.loaded = true;
        }
    }

    Component.onCompleted: root.reload()
}
