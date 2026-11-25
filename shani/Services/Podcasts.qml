pragma Singleton
// Podcasts: the podcast half of the feed client. The bridge (feeds.py) owns the
// subscription list, the polling cache and the enclosures; this service is the
// view of it: recent episodes, favourites, the download queue, the position
// last-played episodes were left at. Playing goes through PlayQueue like every
// other media in the shell.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property string tool: Quickshell.env("SHANI_FEEDS_TOOL") || "/usr/lib/shani-shell/feeds.py"
    property var feeds: []              // [{ title, url, items, unread }] from `list`
    property string search: ""
    property var searchResults: []
    property var favourites: []         // "url|id", newest first
    property string sortOrder: "newest" // newest | oldest | title
    property string note: ""            // last successful action
    property string error: ""           // last failure, including a missing tool
    property bool busy: false           // the single guard for the feeds Process
    property string lastFeed: ""        // feed followed last, on disk
    property string lastEpisode: ""     // "url|id" of the episode left open
    property string currentFeed: ""     // restored when the window opens
    property string currentEpisode: ""

    // ---- persisted: favourites and where last-played episodes were left ---
    property var lastPlayed: ({})       // "url|id" -> seconds; streams have none
    FileView {
        id: stateStore
        path: Quickshell.statePath("podcast-state.json")
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text()) || {};
                if (Array.isArray(d.favourites)) root.favourites = d.favourites;
                if (d.lastPlayed) root.lastPlayed = d.lastPlayed;
                if (d.lastFeed) root.lastFeed = d.lastFeed;
                if (d.lastEpisode) root.lastEpisode = d.lastEpisode;
            } catch (e) {}
        }
    }
    function saveState() {
        stateStore.setText(JSON.stringify({
            favourites: root.favourites,
            lastPlayed: root.lastPlayed,
            lastFeed: root.lastFeed,
            lastEpisode: root.lastEpisode
        }));
    }
    // the window calls this when it opens: the last feed and episode come back
    // as the current ones, not just as numbers on disk
    function restore() {
        root.currentFeed = root.lastFeed;
        root.currentEpisode = root.lastEpisode;
    }
    function lastFor(url, id) { return root.lastPlayed[url + "|" + id] || 0 }
    function toggleFavourite(url, id) {
        const key = url + "|" + id;
        const rest = root.favourites.filter(k => k !== key);
        root.favourites = root.favourites.indexOf(key) >= 0 ? rest
            : [key].concat(rest).slice(0, 100);
        root.saveState();
    }

    // ---- feeds ----------------------------------------------------------------
    function run(what, args) {
        if (job.running || root.busy) { root.pending = { what: what, args: args }; return; }
        root.busy = true;
        job.what = what;
        job.command = ["python3", root.tool, what].concat(args);
        job.running = true;
    }
    property var pending: null
    function addFeed(url, title) { root.run("add", url ? [url.trim()].concat(title ? [title] : []) : []) }
    // a handoff from Feeds: remember the feed before asking the bridge to add
    // it, so a failed add still leaves something to restore on the next open
    function listenToFeed(url) {
        const u = String(url || "").trim();
        if (!u) { root.note = Tr.t("No feed address to listen to"); return; }
        root.lastFeed = u;
        root.currentFeed = u;
        root.saveState();
        root.addFeed(u);
    }
    function removeFeed(url) { root.run("remove", [url]) }
    function searchFeeds(q) {
        root.search = q;
        if (q) root.run("search", [q]);
        else root.searchResults = [];
    }

    // where each last-played episode was left, polled while the player runs
    Timer {
        id: playPoll
        interval: 1000
        running: PlayQueue.shown
        onTriggered: {
            const cur = PlayQueue.current;
            if (!cur) return;
            const row = root.episodes.find(e => e.enclosure && e.enclosure.url === cur);
            if (row) {
                row.played = PlayQueue.playing;
                row.resumeAt = PlayQueue.position;
                root.lastPlayed[row.url + "|" + row.id] = PlayQueue.position;
            }
        }
    }

    // ---- episodes: cached items of the followed feeds, in sort order ------
    property var episodes: []           // [{ url, id, title, date, summary, enclosure, fav, played, resumeAt }]
    property int episodesBusy: 0
    function sorted(rows) {
        const list = (rows || []).slice();
        const key = r => root.sortOrder === "title" ? String(r.title || "") : String(r.date || "");
        list.sort((a, b) => { const x = key(a), y = key(b); return x < y ? -1 : x > y ? 1 : 0; });
        return root.sortOrder === "newest" ? list.reverse() : list;
    }
    function episodesFor(url) {
        const eps = root.episodes.filter(r => r.url === url);
        return eps.length ? root.sorted(eps) : root.episodes;
    }

    // ---- playing: through the media player's queue, like every media ------
    function play(url, id) {
        const row = root.episodes.find(e => e.url === url && e.id === id);
        const enc = row && row.enclosure && row.enclosure.url;
        if (!enc) { root.note = Tr.t("That episode has no audio to play"); return; }
        root.note = "";
        root.lastFeed = url;
        root.lastEpisode = url + "|" + id;
        root.currentFeed = url;
        root.currentEpisode = root.lastEpisode;
        root.saveState();
        if (PlayQueue.validStreamUrl(enc))
            PlayQueue.playStream(enc, row.title || url);
        else
            PlayQueue.open(enc);
    }

    // ---- downloads: one Process per file, a row per episode ---------------
    property var downloads: []          // [{ url, name, state, size }], state: queued|downloading|done|failed
    property bool dlRunning: false
    function download(url, name) {
        if (!url) return;
        const safe = String(name || url.split("/").pop() || "episode")
            .replace(/[^A-Za-z0-9._-]+/g, "_").slice(0, 60);
        root.downloads = root.downloads.concat([{ url, name: safe, state: "queued", size: 0 }]);
        if (!root.dlRunning) root.startNext();
    }
    function startNext() {
        const row = root.downloads.find(r => r.state === "queued");
        if (!row) return;
        root.dlRunning = true;
        dl.row = row;
        dl.command = ["curl", "-fL", "-o", root.downloadDir() + row.name + ".part", row.url];
        dl.running = true;
    }
    function downloadDir() {
        const p = Quickshell.statePath("podcasts");
        return p.endsWith("/") ? p : p + "/";
    }
    Process {
        id: dl
        property var row
        onStarted: root.setDownload(dl.row, "downloading")
        onExited: code => {
            const row = root.downloads.find(r => r === dl.row);
            if (row) row.state = code === 0 ? "done" : "failed";
            root.dlRunning = false;
            root.startNext();
        }
    }
    function setDownload(row, state) {
        const r = root.downloads.find(x => x === row);
        if (r) r.state = state;
    }

    // ---- feeds.py machinery ----------------------------------------------
    Process {
        id: job
        property string what: ""
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.busy = false;
            if (code === 127) { root.error = Tr.t("The feed service is not installed"); return; }
            if (code !== 0) { root.error = Tr.t("The feed service could not answer"); return; }
            root.finished(job.what, out.text);
            if (root.pending) {
                const next = root.pending;
                root.pending = null;
                root.run(next.what, next.args);
            }
        }
    }
    function finished(what, text) {
        let data;
        try { data = JSON.parse(text); } catch (e) { root.error = Tr.t("The feed service sent something unreadable"); return; }
        root.error = "";
        if (what === "list") {
            root.feeds = Array.isArray(data) ? data : [];
            root.episodes = [];
            root.feeds.forEach(f => root.run("items", [f.url]));
        } else if (what === "items") {
            const rows = (Array.isArray(data) ? data : [])
                .filter(r => r && r.id);
            if (rows.length) {
                // one feed's items, or the next feed's when an earlier is empty
                const seen = new Set();
                root.episodes = root.episodes.concat(rows.filter(r => {
                    const k = r.url + "|" + r.id;
                    if (seen.has(k)) return false;
                    seen.add(k);
                    r.played = false;
                    r.resumeAt = root.lastFor(r.url, r.id);
                    return true;
                }));
            }
            root.episodes = root.sorted(root.episodes);
        } else if (what === "add") {
            root.note = data && data.ok ? Tr.t("Feed added") : Tr.t("Could not add that feed");
            root.run("list", []);
        } else if (what === "remove") {
            root.note = Tr.t("Feed removed");
            root.run("list", []);
        } else if (what === "search") {
            root.searchResults = Array.isArray(data) ? data : [];
        }
    }
    Component.onCompleted: { root.run("list", []); }
}
