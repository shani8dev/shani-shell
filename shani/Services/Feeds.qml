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

    function refresh() { run("list", []) }
    function open(url) { current = url; article = ""; run("items", [url]) }
    function show(url, id) { openId = id; run("article", [url, id]) }
    function markRead(url, id) { if (id) run("markread", [url, id], false) }
    function add(url, title) { run("add", title ? [url, title] : [url]) }
    function remove(url) { run("remove", [url]) }
    function update() { busy = true; run("refresh", []) }

    // "2026-11-21T10:00:00+00:00" -> "10:00" today, "21 Nov" otherwise
    function when(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        if (isNaN(d.getTime())) return String(iso).slice(0, 10);
        if (d.toDateString() === new Date().toDateString()) return Qt.formatTime(d, "HH:mm");
        return Qt.formatDate(d, "d MMM");
    }

    // one Process, reused: `what` says which answer this is, and the handlers
    // below pick it up. A change never runs two at once.
    function run(what, args, redraw) {
        if (job.running) return;
        job.what = what;
        job.redraw = redraw !== false;
        job.command = ["python3", root.tool].concat(args);
        job.running = false;
        job.running = true;
    }

    function finished(what, text, code) {
        busy = false;
        if (code !== 0) {
            root.note = Tr.t("The feed reader could not answer");
            return;
        }
        let data = null;
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
        }
    }

    Process {
        id: job
        property string what: ""
        property bool redraw: true
        stdout: StdioCollector { id: out }
        onExited: code => root.finished(job.what, out.text, code)
    }

    Component.onCompleted: refresh()
}