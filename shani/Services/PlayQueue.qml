pragma Singleton
// The Media Player's queue (Modules/MediaPlayer shows and plays it): the file
// asked for and, after it, the other videos or songs in its folder - so Next
// goes to the next episode or track, as a player is expected to. What is
// playing, where it is and how long it is are written here by the window, so
// `state` and the CLI can read them; play/pause, seek and volume asked over
// IPC are signals the window answers.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property bool shown: false
    // the window's page: "library" (the music and videos) or "playing"
    property string page: "library"
    property var queue: []                // absolute paths
    property int index: -1
    readonly property string current: index >= 0 && index < queue.length ? queue[index] : ""
    readonly property string name: isStream ? (streamNames[current] || current) : current.split("/").pop()
    // a radio station (Radio.qml): its address in the queue, its name and picture here.
    // Cameras (rtsp), live feeds (rtmp) and http(s) all go straight to the
    // player: one allowlist, no shell, no local-file fallback for a URL.
    readonly property var streamSchemes: ["http", "https", "rtsp", "rtsps", "rtmp", "rtmps", "rtmpe", "udp", "tcp", "srt", "ftp", "ftps", "mms", "mmsh"]
    function validStreamUrl(u) {
        const m = /^([a-z][a-z0-9+.-]*):\/\//i.exec(String(u || "").trim());
        return !!m && root.streamSchemes.indexOf(m[1].toLowerCase()) >= 0;
    }
    readonly property bool isStream: validStreamUrl(current)
    property var streamNames: ({})
    property string streamPicture: ""
    function playStream(url, title, picture) {
        const n = Object.assign({}, root.streamNames); n[url] = title || url; root.streamNames = n;
        root.streamPicture = picture || "";
        root.playList([url], 0);
        root.opened();                        // the window goes to Now playing
    }
    // off | all | one — MPRIS None | Playlist | Track
    property string repeat: "off"
    readonly property bool repeatOne: repeat === "one"   // kept for readers of the old flag
    property bool shuffle: false
    // the window's readings
    property bool playing: false
    property bool hasVideo: false
    property real position: 0             // seconds
    property real duration: Theme.mot(0)
    property string error: ""
    property real volume: 1
    property bool muted: false
    property real rate: 1
    // MPRIS and the CLI can ask for anything: clamp here so a NaN never reaches
    // AudioOutput (Math.min(1, NaN) is NaN, and a NaN volume stays NaN)
    function clampVolume(v) {
        const n = Number(v);
        return isFinite(n) ? Math.max(0, Math.min(1, n)) : 0;
    }
    function clampSeek(seconds, length) {
        const n = Number(seconds), end = Number(length);
        return Math.max(0, Math.min(isFinite(end) && end > 0 ? end : 0, isFinite(n) ? n : 0));
    }

    // ---- where each long video or song was left: it starts there again ----
    // (over two minutes long, more than ten seconds in, not near the end;
    // the newest 300 kept, in the shell's state folder)
    property var resumeAt: ({})           // path -> seconds
    property real resumedFrom: 0          // where the one playing was resumed from (0: from the start)
    property string resumedPath: ""       // which file that was: only another one clears it
    function remember(path, pos, dur) {
        if (!path || dur < 120 || root.validStreamUrl(path)) // a stream has no place to come back to
            return;
        const m = Object.assign({}, resumeAt);
        delete m[path];
        if (pos > 10 && pos < dur * 0.95)
            m[path] = Math.round(pos);
        const keys = Object.keys(m);
        for (let i = 0; i < keys.length - 300; i++)
            delete m[keys[i]];
        resumeAt = m;
        resumeSave.restart();
    }
    function forget(path) { remember(path, 0, 9999); }
    function resumePoint(path) { return resumeAt[path] || 0; }
    // the old resume-only reading, kept for readers that want it; the UI now
    // shows the persisted recent list below, which includes streams as well
    readonly property var resumeRecent: Object.keys(resumeAt).sort((a, b) => resumeAt[b] - resumeAt[a])
    FileView {
        id: resumeStore
        path: Quickshell.statePath("media-resume.json")
        printErrors: false                 // none yet: nothing left halfway
        onLoaded: { try { root.resumeAt = JSON.parse(text()) || {}; } catch (e) {} }
    }
    Timer { id: resumeSave; interval: 1500; onTriggered: resumeStore.setText(JSON.stringify(root.resumeAt)) }

    // ---- recent media: the last things played, newest first, kept in a
    // sibling of the settings file (as OSK does) so a restart does not forget
    // them. Streams are listed by address; resume points stay in resumeAt.
    readonly property string recentPrefsDir: {
        const p = Settings.path;
        return p.substring(0, p.lastIndexOf("/"));
    }
    readonly property int recentCap: 20
    FileView {
        id: recentFile
        path: root.recentPrefsDir + "/media-recent.json"
        atomicWrites: true
        printErrors: false
        onLoaded: root.recentLoaded = true
        onLoadFailed: root.recentLoaded = true
        onAdapterUpdated: root.recentLoaded = true
        // a list of JSON strings: JsonAdapter reads typed lists, not a bare var
        JsonAdapter { id: recentPrefs; property list<string> items: [] }
    }
    property bool recentLoaded: false
    // pure: one row per address, newest first, never longer than recentCap
    function recentAdd(items, entry) {
        if (!entry || !entry.path)
            return items;
        const p = String(entry.path);
        const rest = (items || []).filter(x => x && x.path !== p);
        return [Object.assign({ path: p, title: "", at: 0 }, entry)].concat(rest).slice(0, root.recentCap);
    }
    readonly property var recentRows: (recentPrefs.items || []).map(s => {
        try { return JSON.parse(s); } catch (e) { return null; }
    }).filter(x => x && x.path)
    readonly property var recent: recentRows.map(x => x.path)
    function rememberRecent(path, title) {
        if (!root.recentLoaded || !path)
            return;
        recentPrefs.items = root.recentAdd(root.recentRows, { path: String(path), title: title || "", at: Date.now() }).map(x => JSON.stringify(x));
        recentFile.writeAdapter();
    }
    function playRecent(path) {
        if (!path)
            return;
        if (root.validStreamUrl(path))
            root.playStream(path);
        else
            root.open(path);
    }
    function clearRecent() {
        recentPrefs.items = [];
        recentFile.writeAdapter();
    }

    // ---- playlists of its own: the person's own lists, kept as JSON in the
    // shell's state folder (like the resume points), each { name, paths }.
    // The queue is session-only; these survive a restart. No m3u: a plain JSON
    // list is the shell's own format and the Library reads it back directly.
    property var playlists: []              // [{ name, paths: [] }]
    function findPlaylist(name) { return playlists.find(p => p.name === name) || null; }
    function savePlaylist(name, paths) {
        name = String(name || "").trim();
        if (name === "" || !paths || paths.length === 0)
            return false;
        const list = paths.map(p => String(p));
        const rest = playlists.filter(p => p.name !== name);
        playlists = rest.concat([{ name: name, paths: list }]);
        playlistStore.setText(JSON.stringify(playlists));
        return true;
    }
    // the queue as it stands, under a name (the Library's "Save as playlist")
    function saveQueueAs(name) { return root.savePlaylist(name, root.queue); }
    function openPlaylist(name) {
        const p = root.findPlaylist(name);
        if (p && p.paths.length)
            root.playList(p.paths, 0);
    }
    // add one file to a playlist (the playing one, by default), no duplicates
    function addToPlaylist(name, path) {
        const p = root.findPlaylist(name);
        if (!p)
            return false;
        const one = String(path || root.current || "");
        if (one === "" || p.paths.indexOf(one) >= 0)
            return false;
        const rest = playlists.filter(x => x.name !== name);
        playlists = rest.concat([{ name: name, paths: p.paths.concat([one]) }]);
        playlistStore.setText(JSON.stringify(playlists));
        return true;
    }
    function addPlayingTo(name) { return root.addToPlaylist(name, root.current); }
    function deletePlaylist(name) {
        playlists = playlists.filter(p => p.name !== name);
        playlistStore.setText(JSON.stringify(playlists));
    }
    FileView {
        id: playlistStore
        path: Quickshell.statePath("media-playlists.json")
        printErrors: false                 // none yet: no list saved
        onLoaded: {
            try {
                const v = JSON.parse(text()) || [];
                // tolerate the old shape (a bare list of paths) by giving it a name
                root.playlists = v.map(p => Array.isArray(p) ? { name: "", paths: p } : p).filter(p => p && p.name && p.paths);
            } catch (e) {}
        }
    }

    // ---- .m3u in and out: bridge/playlist.py parses and writes the format;
    // the queue owns the entries. Only local paths and allowed stream
    // addresses are taken back in, so a playlist cannot point the player at
    // anything else. The bridge takes argv only and never runs a shell.
    readonly property string playlistTool: Quickshell.env("SHANI_PLAYLIST_TOOL") || "/usr/lib/shani-shell/playlist.py"
    property string playlistNote: ""
    function saveQueueM3u(path) {
        const p = String(path || "").trim();
        if (!p.startsWith("/") || root.queue.length === 0)
            return false;
        const entries = root.queue.map(x => ({ path: x, title: root.streamNames[x] || "" }));
        m3uWrite.running = false;
        m3uWrite.command = ["python3", root.playlistTool, "write", p, JSON.stringify({ entries: entries })];
        m3uWrite.running = true;
        return true;
    }
    function loadPlaylistM3u(path) {
        const p = String(path || "").trim();
        if (!p.startsWith("/"))
            return false;
        m3uRead.running = false;
        m3uRead.command = ["python3", root.playlistTool, "read", p];
        m3uRead.running = true;
        return true;
    }
    Process {
        id: m3uWrite
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) {}
                root.playlistNote = d.error || (d.ok ? Tr.t("Saved %1 tracks", d.count) : Tr.t("Could not save the playlist"));
            }
        }
        onExited: code => { if (code !== 0) root.playlistNote = Tr.t("Could not save the playlist"); }
    }
    Process {
        id: m3uRead
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) {}
                if (d.error) { root.playlistNote = d.error; return; }
                const found = d.entries || [];
                const paths = found.map(x => String(x.path || "")).filter(x => x.startsWith("/") || root.validStreamUrl(x));
                const names = {};
                for (const x of found) if (x.title && x.path) names[x.path] = x.title;
                root.streamNames = Object.assign({}, root.streamNames, names);
                if (paths.length) {
                    root.playList(paths, 0);
                    root.playlistNote = Tr.t("Loaded %1 tracks", paths.length);
                } else
                    root.playlistNote = Tr.t("That playlist is empty");
            }
        }
        onExited: code => { if (code !== 0) root.playlistNote = Tr.t("Could not read the playlist"); }
    }

    // ---- A→B loop: jump back to A when the playhead passes B ----
    property real loopA: -1
    property real loopB: -1
    readonly property bool loopActive: loopA >= 0 && loopB > loopA
    function setLoopA(at) { loopA = Math.max(0, Number(at) || 0); if (loopB <= loopA) loopB = -1; }
    function setLoopB(at) { if (loopA < 0) return; const v = Number(at) || 0; if (v > loopA) loopB = v; }
    function clearLoop() { loopA = -1; loopB = -1; }
    // the position to seek to when the playhead passes B, else -1 (the window owns the player)
    function loopJump(pos) { return loopActive && pos >= loopB ? loopA : -1; }

    // ---- chapters, from ffprobe when it is present ----
    // [{ title, start, end }] in seconds. Read only for a file that can have
    // them (a video): ffprobe answers with an empty list for the rest, and its
    // absence degrades to no chapters rather than an error.
    property var chapters: []
    Process {
        id: chapterProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const cs = (JSON.parse(text) || {}).chapters || [];
                    root.chapters = cs.filter(c => c && isFinite(parseFloat(c.start_time)))
                        .map(c => ({ title: (c.tags && c.tags.title) || "",
                                     start: parseFloat(c.start_time) || 0,
                                     end: parseFloat(c.end_time) || 0 }));
                } catch (e) { root.chapters = []; }
            }
        }
    }

    // a subtitle file beside the video: "film.mkv" -> "film.srt" (or .vtt, or "film.en.srt")
    property string subtitleFile: ""
    // how far the subtitle track is moved from what the file says, in seconds.
    // Per file: a delay is a property of that rip, and carrying it into the
    // next one would be worse than asking again.
    property real subtitleShift: 0
    function setSubtitleShift(s) { subtitleShift = Math.max(-60, Math.min(60, Number(s) || 0)); }
    onCurrentChanged: {
        tellMpris();
        root.rememberRecent(current, root.streamNames[current] || "");
        if (current !== resumedPath) { resumedFrom = 0; resumedPath = ""; }
        subtitleFile = "";
        root.chapters = [];
        if (current && kind(current) === "video") {
            subFinder.command = ["sh", "-c", 'b=${1%.*}; for f in "$b.srt" "$b.vtt" "$b".*.srt "$b".*.vtt; do [ -f "$f" ] && { printf "%s" "$f"; exit 0; }; done; exit 0', "sh", current];
            subFinder.running = true;
            if (!isStream) {
                chapterProc.command = ["ffprobe", "-v", "error", "-show_chapters", "-of", "json", "--", current];
                chapterProc.running = true;
            }
        }
    }
    Process {
        id: subFinder
        stdout: StdioCollector { onStreamFinished: root.subtitleFile = text.trim() }
    }

    // what the window shows, for `state` and the tests
    property bool mini: false
    signal miniRequested(bool on)
    property string cue: ""               // the subtitle line on screen now
    // the player's key legend, in one place: a hint area can show it and the
    // button tips repeat the same keys without having to guess them
    readonly property string keyHints: "Space play/pause · ← → seek · M mute · F fullscreen · P/N playlist"
    property int audioTrackCount: 0
    property string tagLine: ""           // the song's own title and artist, when read from the file
    property string coverShown: ""

    signal playRequested()
    signal pauseRequested()
    signal toggleRequested()
    signal frameRequested()                 // save the frame on screen (the window does it)
    signal seekRequested(real seconds)

    readonly property var videoTypes: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "mpg", "mpeg", "ogv", "wmv", "flv", "3gp", "ts"]
    readonly property var audioTypes: ["mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav", "wma", "aiff", "mka"]
    function kind(path) {
        const ext = String(path).split(".").pop().toLowerCase();
        return videoTypes.indexOf(ext) >= 0 ? "video" : audioTypes.indexOf(ext) >= 0 ? "audio" : "";
    }

    // a file ("" just opens the player), a file:// URI, or a folder (its files in order)
    signal opened()
    function open(arg) {
        root.shown = true;
        // reopening the same file is a new viewing: any timing fix belonged to
        // the last one (onCurrentChanged does not fire for the same path)
        root.subtitleShift = 0;
        if (String(arg || "").trim() !== "")
            root.opened();
        root.error = "";
        let path = String(arg || "").trim();
        if (path.startsWith("file://"))
            path = decodeURIComponent(path.substring(7));
        if (path === "")
            return;
        if (!path.startsWith("/"))
            path = (Quickshell.env("HOME") || "") + "/" + path;
        // it plays at once; the folder's other files join the queue when they are listed
        root.queue = [path];
        root.index = 0;
        root.history = [];
        root.playRequested();
        siblings.want = path;
        siblings.command = ["sh", "-c", 'if [ -d "$1" ]; then d=$1; else d=${1%/*}; fi; find "$d" -maxdepth 1 -type f -printf "%p\\n" 2>/dev/null | sort -V | head -2000', "sh", path];
        siblings.running = true;
    }
    Process {
        id: siblings
        property string want: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const first = siblings.want;
                const wanted = root.kind(first);
                // of its kind: an album's songs after a song, not the cover picture
                const all = text.split("\n").filter(p => p !== "" && (wanted === "" ? root.kind(p) !== "" : root.kind(p) === wanted));
                if (all.length === 0)
                    return;
                const at = all.indexOf(first);
                if (at < 0 && wanted !== "")
                    return;            // the file is not in its folder's listing (gone already)
                if (root.queue.length === 1 && root.queue[0] === first || wanted === "") {
                    root.queue = all;
                    root.index = Math.max(0, at);
                    root.history = [];
                    if (wanted === "")
                        root.playRequested();
                }
            }
        }
    }

    // a list chosen elsewhere (the Library's album, its songs), from one of them
    function playList(paths, at) {
        if (!paths || paths.length === 0)
            return;
        root.shown = true;
        root.error = "";
        root.queue = paths.slice();
        root.index = Math.max(0, Math.min(paths.length - 1, at || 0));
        root.history = [];
        root.playRequested();
    }
    // the indices we actually played, so Back retraces a shuffle jump too
    property var history: []
    function go(i) {
        if (i < 0 || i >= queue.length)
            return;
        if (index >= 0 && i !== index) {
            const h = history.slice(); h.push(index); history = h;
        }
        index = i;
        playRequested();
    }
    // edits keep `current` pointing at a real row
    function remove(i) {
        if (i < 0 || i >= queue.length)
            return;
        const wasCurrent = i === index, wasPlaying = playing;
        const q = queue.slice(); q.splice(i, 1);
        queue = q;
        history = [];                    // the old indices no longer mean anything
        if (i < index) index--;
        else if (index >= q.length) index = q.length - 1;
        if (q.length === 0) { playing = false; position = 0; }
        else if (wasCurrent && wasPlaying) playRequested();
    }
    function clear() {
        queue = [];
        index = -1;
        history = [];
        playing = false;
        position = 0;
    }
    function next() {
        if (queue.length < 2)
            return;
        go(shuffle ? Math.floor(Math.random() * queue.length) : (index + 1) % queue.length);
    }
    function previous() {
        // as players do: back to the start first, the one before only from the start
        if (position > 3 || queue.length < 2) {
            seekRequested(0);
            return;
        }
        if (history.length) {
            const h = history.slice(), prev = h.pop();
            history = h;
            index = prev;
            playRequested();
        } else
            go((index - 1 + queue.length) % queue.length);
    }
    // the file ended: replay it, play on through the queue, or stop at the last
    function ended() {
        if (repeat === "one" || (repeat === "all" && queue.length === 1)) {
            seekRequested(0);
            playRequested();
        } else if (repeat === "all" || shuffle || index < queue.length - 1)
            next();
    }
    // Stop: pause and rewind (what MPRIS stop means); the file stays queued
    function stop() { pauseRequested(); seekRequested(0); playing = false; position = 0; }
    function close() {
        shown = false;
        page = current === "" ? "library" : page;
        playing = false;
    }
    // ---- MPRIS (bridge/mpris-player.py): what the bar, the sidebar, the lock
    // screen and the media keys read - they see this player as they see any other
    readonly property string mprisTool: Quickshell.env("SHANI_MPRIS_TOOL") || "/usr/lib/shani-shell/mpris-player.py"
    function mprisState() {
        return JSON.stringify({ status: current === "" ? "Stopped" : playing ? "Playing" : "Paused", title: name,
            url: current !== "" ? (isStream ? current : "file://" + current.split("/").map(encodeURIComponent).join("/")) : "",
            length: duration, position: position, volume: muted ? 0 : volume, rate: rate,
            canNext: queue.length > 1, canPrevious: queue.length > 1,
            loop: repeat === "one" ? "Track" : repeat === "all" ? "Playlist" : "None", shuffle: shuffle }) + "\n";
    }
    function tellMpris() { if (mpris.running) mpris.write(mprisState()); }
    onPlayingChanged: tellMpris()
    onDurationChanged: tellMpris()
    onVolumeChanged: tellMpris()
    onMutedChanged: tellMpris()
    onRateChanged: tellMpris()
    onRepeatChanged: tellMpris()
    onShuffleChanged: tellMpris()
    onQueueChanged: tellMpris()
    onSeekRequested: seconds => { if (mpris.running) mpris.write(JSON.stringify({ seeked: seconds }) + "\n"); }
    // the position, for a client that asks, once a second while playing (not per frame)
    Timer { interval: 1000; repeat: true; running: root.playing && mpris.running; onTriggered: root.tellMpris() }
    signal raiseRequested()
    Process {
        id: mpris
        running: root.shown
        command: ["python3", root.mprisTool]
        stdinEnabled: true
        onStarted: root.tellMpris()
        stdout: SplitParser {
            onRead: line => {
                let c = null;
                try { c = JSON.parse(line); } catch (e) { return; }
                if (c.op === "play") root.playRequested();
                else if (c.op === "pause") root.pauseRequested();
                else if (c.op === "toggle") root.toggleRequested();
                else if (c.op === "stop") { root.pauseRequested(); root.seekRequested(0); }
                else if (c.op === "next") root.next();
                else if (c.op === "previous") root.previous();
                else if (c.op === "seek") root.seekRequested(clampSeek(c.to, root.duration));
                else if (c.op === "volume") { root.muted = false; root.volume = clampVolume(c.value); }
                else if (c.op === "rate") root.rate = Math.max(0.25, Math.min(4, Number(c.value) || 1));
                else if (c.op === "loop") root.repeat = c.value === "Track" ? "one" : c.value === "Playlist" ? "all" : "off";
                else if (c.op === "shuffle") root.shuffle = !!c.value;
                else if (c.op === "open") root.open(c.uri);
                else if (c.op === "raise") root.raiseRequested();
                else if (c.op === "quit") root.close();
            }
        }
    }

    function clock(s) {
        const t = Math.max(0, Math.floor(s)), h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), sec = t % 60;
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(sec).padStart(2, "0");
    }
}
