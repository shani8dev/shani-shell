pragma Singleton
// RSS and Atom feeds: bridge/feeds.py owns the subscription list, the cache and
// the reading state, so the window is a view and nothing else.
//
// The feeds are fetched by the bridge on demand (add / refresh) and read from
// its cache otherwise, so opening the reader never waits on the network.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_FEEDS_TOOL") || "/usr/lib/shani-shell/feeds.py"

    property var feeds: []          // [{ title, url, items, unread }]
    property string current: ""     // the feed being read
    property var items: []          // its items: [{ id, title, link, date, summary, read }]
    property string article: ""     // the open article's text
    property string articleTitle: ""
    property string articleLink: ""
    property string openId: ""       // the article being read, for the read flag
    property bool busy: false
    property string note: ""
    property int refreshMinutes: 0  // refresh every so often, 0 = never on its own
    property string opml: ""        // the last exported document
    property string pendingExport: ""   // where "Export…" is writing
    property string exportPath: ""   // the same, for the writer's command

    function refresh() { run("list", []) }
    function open(url) { current = url; article = ""; run("items", [url]) }
    function show(url, id) { openId = id; run("article", [url, id]) }
    function markRead(url, id) { if (id) run("markread", [url, id], false) }
    function add(url, title) { run("add", title ? [url, title] : [url]) }
    function remove(url) { run("remove", [url]) }
    function update() { busy = true; run("refresh", []) }
    function check() { run("status", []) }
    function setInterval(n) { run("interval", [String(n)]) }

    // ---- moving the subscription list -------------------------------------
    // OPML 2.0, the one format every other reader reads: out to a file the
    // person picks, in from one - ours, or another reader's
    function exportDialog() {
        FilePicker.open({
            mode: "save",
            defaultName: "feeds.opml",
            title: Tr.t("Save the subscriptions as OPML…"),
            onPicked: paths => root.exportTo(paths[0]),
        });
    }
    function exportTo(path) { root.pendingExport = path; run("export", []) }
    function importDialog() {
        FilePicker.open({
            mode: "open",
            filters: ["opml", "xml", "json"],
            title: Tr.t("Add the feeds in an OPML file…"),
            onPicked: paths => root.run("import", [paths[0]]),
        });
    }

    // the person's own timer, not a poller: it only exists while an interval
    // is set, and one tick costs one python process
    Timer {
        interval: Math.max(1, root.refreshMinutes) * 60000
        running: root.refreshMinutes > 0
        repeat: true
        onTriggered: root.update()
    }

    // "2026-11-21T10:00:00+00:00" -> "10:00" today, "21 Nov" otherwise
    function when(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        if (isNaN(d.getTime())) return String(iso).slice(0, 10);
        if (d.toDateString() === new Date().toDateString()) return Qt.formatTime(d, "HH:mm");
        return Qt.formatDate(d, "d MMM");
    }

    // one Process, reused: `what` says which answer this is, and the handlers
    // below pick it up. A change never runs two at once — but one that arrives
    // while another is running is kept and run next, not dropped: the singleton
    // is created by the first thing that touches it, and its own first fetch
    // would otherwise swallow that thing.
    function run(what, args, redraw) {
        if (job.running) { root.pending = { what: what, args: args, redraw: redraw !== false }; return; }
        root.start(what, args, redraw);
    }

    function start(what, args, redraw) {
        job.what = what;
        job.redraw = redraw !== false;
        // the subcommand is part of the command line: `feeds.py items <url>`,
        // not `feeds.py <url>` - the latter answers with the usage line
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }

    property var pending: null

    function finished(what, text, code) {
        busy = false;
        if (code !== 0) {
            root.note = Tr.t("The feed reader could not answer");
            return;
        }
        let data = null;
        if (what === "export") {
            // OPML, not JSON: the document is the answer
            root.opml = text;
            if (root.pendingExport) {
                const path = root.pendingExport;
                root.pendingExport = "";
                root.exportPath = path;
                writer.running = true;
                root.note = Tr.t("Saved to %1", path);
            }
            return;
        }
        try { data = JSON.parse(text); } catch (e) { root.note = Tr.t("The feed reader sent something unreadable"); return; }
        if (what === "list") {
            root.feeds = Array.isArray(data) ? data : [];
            if (!root.current && root.feeds.length) root.open(root.feeds[0].url);
        } else if (what === "items") {
            root.items = Array.isArray(data) ? data : [];
            if (root.items.length) root.show(root.current, root.items[0].id);
        } else if (what === "article") {
            root.articleTitle = (data && data.title) || "";
            root.articleLink = (data && data.link) || "";
            root.article = (data && data.text) || "";
            root.markRead(root.current, root.openId);
        } else if (what === "add" || what === "refresh" || what === "remove") {
            root.refresh();
        } else if (what === "status") {
            root.refreshMinutes = (data && data.interval) || 0;
        } else if (what === "interval") {
            root.refreshMinutes = (data && data.interval) || 0;
            root.note = root.refreshMinutes > 0
                ? Tr.t("Refreshing every %1 minutes", root.refreshMinutes)
                : Tr.t("Refreshing only when you ask");
        } else if (what === "import") {
            const added = (data && data.added) || 0;
            root.note = added > 0
                ? Tr.t("Added %1 feeds", added)
                : Tr.t("Every feed in that file is already here");
            root.refresh();
        }
    }

    // the export goes out through a process, like every other write in the
    // shell: a path the picker chose is a path the person owns
    Process {
        id: writer
        command: ["sh", "-c", 'f=$1; mkdir -p "${f%/*}" 2>/dev/null; printf "%s" "$2" > "$f"', "sh",
                  root.exportPath, root.opml]
    }

    Process {
        id: job
        property string what: ""
        property bool redraw: true
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.finished(job.what, out.text, code);
            if (root.pending) {
                const next = root.pending;
                root.pending = null;
                root.start(next.what, next.args, next.redraw);
            }
        }
    }

    Component.onCompleted: { refresh(); check() }
}