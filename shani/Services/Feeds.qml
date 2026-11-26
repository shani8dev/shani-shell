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
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_FEEDS_TOOL"), "feeds.py")

    property var feeds: []          // [{ title, url, items, unread, tags }]
    property string current: ""     // the feed being read
    property var items: []          // its items: [{ id, title, link, date, summary, read, saved, enclosure }]
    property string article: ""     // the open article's text
    property string articleTitle: ""
    property string articleLink: ""
    property string articleEnclosure: ""   // a podcast episode's audio URL
    property bool articleSaved: false
    property string openId: ""       // the article being read, for the read flag
    property bool busy: false
    property string note: ""        // last successful action
    property string error: ""       // last failure, including a missing tool
    property int refreshMinutes: 0  // refresh every so often, 0 = never on its own
    property string opml: ""        // the last exported document
    property string pendingExport: ""   // where "Export…" is writing
    property string exportPath: ""   // the same, for the writer's command

    // the extra views a reader needs: a saved pile, a word search and a tag
    property bool showRead: true
    property string query: ""
    property var searchResults: []
    property var saved: []
    property var tags: []
    property string pendingArticle: ""  // an article to show once its feed's items arrive
    property bool autoShow: true        // select the first article after opening a feed

    // reading preferences: a compact article and a chosen order are window-local
    // on purpose — like sort in NetNewsWire, they do not touch the bridge cache
    property string readerMode: "full"  // full | compact
    property string sortOrder: "newest" // newest | oldest | title
    property string articleUrl: ""      // the feed the open article came from, so
                                        // save/read act on it even from a search

    function setReaderMode(mode) { root.readerMode = mode === "compact" ? "compact" : "full" }
    function setSort(order) { root.sortOrder = order === "oldest" || order === "title" ? order : "newest" }

    // sort a view's rows without disturbing the cache: search, saved and a feed
    // all get the same order. Title reads A→Z; dates read newest first by default.
    function sorted(items) {
        const list = Array.isArray(items) ? items.slice() : [];
        const key = row => root.sortOrder === "title" ? String(row.title || "") : String(row.date || "");
        list.sort((a, b) => { const x = key(a), y = key(b); return x < y ? -1 : x > y ? 1 : 0; });
        return root.sortOrder === "newest" ? list.reverse() : list;
    }

    // the tag chips double as groups: this is the editable field's value too
    function tagsFor(url) {
        const f = root.feeds.filter(x => x.url === url)[0];
        return f && f.tags ? f.tags.join(", ") : "";
    }
    function unreadTotal() { return root.feeds.reduce((n, f) => n + (f.unread || 0), 0) }

    function refresh() { run("list", []) }
    function open(url) { current = url; article = ""; pendingArticle = ""; autoShow = true; run("items", [url]) }
    function openArticleAt(url, id) { current = url; article = ""; pendingArticle = id; autoShow = false; run("items", [url]) }
    function show(url, id) { articleUrl = url; openId = id; run("article", [url, id]) }
    function markRead(url, id) { if (id) run("markread", [url, id], false) }
    function markUnread(url, id) { if (id) run("markunread", [url, id], false) }
    function nextUnread() { if (current) run("nextunread", [current, openId]) }
    // with no feed there is no safe scope: the bridge's no-argument form marks
    // *everything*, which is never what a header button in one pane means
    function markAll(url) {
        const target = url || root.current;
        if (!target) { root.note = Tr.t("Pick a feed first"); return; }
        run("markall", [target], false);
    }
    function add(url, title) { run("add", title ? [url, title] : [url]) }
    function remove(url) { run("remove", [url]) }
    function update() { run("refresh", []) }
    function check() { run("status", []) }
    function setInterval(n) { run("interval", [String(n)]) }
    function discover(url) { run("discover", [url]) }

    // ---- searching, saving and tagging ------------------------------------
    function search(q) {
        root.query = q;
        if (q) run("search", [q]);
        else root.searchResults = [];
    }
    function savedArticles() { run("saved", []) }
    function toggleSave(url, id) { if (id) run("save", [url, id], false) }
    function setTags(url, tags) { if (url) run("settags", [url, tags]) }
    function loadTags() { run("tags", []) }

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
        // more than one caller can answer the same finished() (settags refreshes
        // the list AND the tag list): a single slot would drop the first one
        if (job.running) { root.pending.push({ what: what, args: args, redraw: redraw !== false }); return; }
        root.start(what, args, redraw);
    }

    function start(what, args, redraw) {
        root.busy = true;
        job.what = what;
        job.redraw = redraw !== false;
        // the subcommand is part of the command line: `feeds.py items <url>`,
        // not `feeds.py <url>` - the latter answers with the usage line
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }

    property var pending: []

    function finished(what, text, code) {
        root.busy = false;
        if (code === 127) {
            root.error = Tr.t("The feed reader is not installed");
            return;
        }
        if (code !== 0) {
            root.error = Tr.t("The feed reader could not answer");
            root.note = "";
            return;
        }
        root.error = "";
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
            if (root.pendingArticle) {
                const id = root.pendingArticle;
                root.pendingArticle = "";
                root.show(root.current, id);
            } else if (root.autoShow && root.items.length) {
                const first = root.sorted(root.items)[0];
                root.show(root.current, first.id);
            }
            root.autoShow = true;
        } else if (what === "article") {
            root.articleTitle = (data && data.title) || "";
            root.articleLink = (data && data.link) || "";
            root.article = (data && data.text) || "";
            root.articleSaved = !!(data && data.saved);
            root.articleEnclosure = (data && data.enclosure && data.enclosure.url) || "";
            root.markRead(root.current, root.openId);
        } else if (what === "add" || what === "refresh" || what === "remove") {
            root.refresh();
        } else if (what === "markread") {
            // opening an article marks it read: the header count and every
            // view showing that row must see the new state, not just the cache
            root.refresh();
            root.savedArticles();
            if (root.query) root.search(root.query);
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
        } else if (what === "nextunread") {
            if (data && data.ok && data.id) root.show(root.current, data.id);
            else root.note = Tr.t("No unread articles left");
        } else if (what === "markall") {
            root.refresh();
            if (root.current) { root.autoShow = false; run("items", [root.current]) }
        } else if (what === "markunread") {
            if (data && data.id) {
                const url = data.url || root.current;
                root.items = root.items.map(i =>
                    i.id === data.id && (!url || i.url === url || root.current === url)
                        ? Object.assign({}, i, { read: false }) : i);
            }
            // the same article can be on screen in a feed, the saved pile or a
            // search: keep all three honest instead of only the feed list
            root.refresh();
            root.savedArticles();
            if (root.query) root.search(root.query);
        } else if (what === "save") {
            if (data && data.id) {
                root.items = root.items.map(i =>
                    i.id === data.id && (!data.url || root.current === data.url || i.url === data.url)
                        ? Object.assign({}, i, { saved: !!data.saved }) : i);
                if (root.openId === data.id) root.articleSaved = !!data.saved;
            }
            root.note = data && data.saved ? Tr.t("Saved for later") : Tr.t("Removed from saved");
            root.savedArticles();
            if (root.query) root.search(root.query);
        } else if (what === "saved") {
            root.saved = Array.isArray(data) ? data : [];
        } else if (what === "search") {
            root.searchResults = Array.isArray(data) ? data : [];
        } else if (what === "settags") {
            root.note = data && data.ok ? Tr.t("Tags updated") : Tr.t("Could not set tags");
            // finished() runs on the collector, before the process has exited:
            // start the two follow-up reads once the job is really free
            Qt.callLater(() => { root.refresh(); root.loadTags(); });
        } else if (what === "tags") {
            root.tags = Array.isArray(data) ? data : [];
        } else if (what === "discover") {
            const found = Array.isArray(data) ? data : [];
            if (found.length) {
                root.note = Tr.t("Found %1 feeds", found.length);
                found.forEach(f => root.add(f.href, f.title));
            } else {
                root.note = data && data.error ? data.error : Tr.t("No feeds found at that address");
            }
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
            if (root.pending.length) {
                const next = root.pending.shift();
                root.start(next.what, next.args, next.redraw);
            }
        }
    }

    Component.onCompleted: { refresh(); check(); loadTags(); savedArticles() }
}
