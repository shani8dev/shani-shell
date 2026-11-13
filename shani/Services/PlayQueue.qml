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
    readonly property string name: current.split("/").pop()
    property bool repeatOne: false
    property bool shuffle: false
    // the window's readings
    property bool playing: false
    property bool hasVideo: false
    property real position: 0             // seconds
    property real duration: 0
    property string error: ""
    property real volume: 1
    property bool muted: false
    property real rate: 1

    // ---- where each long video or song was left: it starts there again ----
    // (over two minutes long, more than ten seconds in, not near the end;
    // the newest 300 kept, in the shell's state folder)
    property var resumeAt: ({})           // path -> seconds
    property real resumedFrom: 0          // where the one playing was resumed from (0: from the start)
    property string resumedPath: ""       // which file that was: only another one clears it
    function remember(path, pos, dur) {
        if (!path || dur < 120)
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
    FileView {
        id: resumeStore
        path: Quickshell.statePath("media-resume.json")
        printErrors: false                 // none yet: nothing left halfway
        onLoaded: { try { root.resumeAt = JSON.parse(text()) || {}; } catch (e) {} }
    }
    Timer { id: resumeSave; interval: 1500; onTriggered: resumeStore.setText(JSON.stringify(root.resumeAt)) }

    // a subtitle file beside the video: "film.mkv" -> "film.srt" (or .vtt, or "film.en.srt")
    property string subtitleFile: ""
    onCurrentChanged: {
        tellMpris();
        if (current !== resumedPath) { resumedFrom = 0; resumedPath = ""; }
        subtitleFile = "";
        if (current && kind(current) === "video") {
            subFinder.command = ["sh", "-c", 'b=${1%.*}; for f in "$b.srt" "$b.vtt" "$b".*.srt "$b".*.vtt; do [ -f "$f" ] && { printf "%s" "$f"; exit 0; }; done; exit 0', "sh", current];
            subFinder.running = true;
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
    property int audioTrackCount: 0
    property string tagLine: ""           // the song's own title and artist, when read from the file
    property string coverShown: ""

    signal playRequested()
    signal pauseRequested()
    signal toggleRequested()
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
        root.playRequested();
    }
    function go(i) {
        if (i < 0 || i >= queue.length)
            return;
        index = i;
        playRequested();
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
        go((index - 1 + queue.length) % queue.length);
    }
    // the file ended: the next one, the same one again, or stop at the last
    function ended() {
        if (repeatOne) {
            seekRequested(0);
            playRequested();
        } else if (shuffle || index < queue.length - 1)
            next();
    }
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
            url: current !== "" ? "file://" + current.split("/").map(encodeURIComponent).join("/") : "",
            length: duration, position: position, volume: muted ? 0 : volume, rate: rate,
            canNext: queue.length > 1, canPrevious: queue.length > 1,
            loop: repeatOne ? "Track" : "None", shuffle: shuffle }) + "\n";
    }
    function tellMpris() { if (mpris.running) mpris.write(mprisState()); }
    onPlayingChanged: tellMpris()
    onDurationChanged: tellMpris()
    onVolumeChanged: tellMpris()
    onMutedChanged: tellMpris()
    onRateChanged: tellMpris()
    onRepeatOneChanged: tellMpris()
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
                else if (c.op === "seek") root.seekRequested(Number(c.to) || 0);
                else if (c.op === "volume") { root.muted = false; root.volume = Math.max(0, Math.min(1, Number(c.value))); }
                else if (c.op === "rate") root.rate = Math.max(0.25, Math.min(4, Number(c.value) || 1));
                else if (c.op === "loop") root.repeatOne = c.value === "Track";
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
