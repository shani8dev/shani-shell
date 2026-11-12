pragma Singleton
// Voice Recorder (GNOME Sound Recorder parity): the microphone, recorded
// with PipeWire's pw-record — the same backend voice typing (Dictation)
// and live captions (Captions) use — as Opus in ~/Music/Voice Recorder,
// date-stamped. Pause is a SIGSTOP on pw-record itself (the file stays
// open; the timer stops with it), stop is SIGINT so the container is
// finalised, and the input level is read from a second, throwaway
// pw-record stream piped through Python (peak of f32 samples every
// 100 ms) because pw-record has no analyser of its own. Playback goes
// to the followed MPRIS player (Media.current.openUri), or xdg-open.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property string state: "idle"        // idle | recording | paused
    readonly property bool recording: state !== "idle"
    readonly property bool paused: state === "paused"
    property string file: ""             // the file being recorded
    property int seconds: 0
    readonly property string elapsed: {
        const h = Math.floor(seconds / 3600), m = Math.floor(seconds % 3600 / 60), s = seconds % 60;
        return String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0");
    }
    property real level: 0               // 0..1 input peak, while recording
    property var recordings: []          // [{ path, name, when }] newest-first
    property string last: ""             // the last file saved (for `state`)
    property string lastPlayed: ""
    property string error: ""
    property bool available: false
    property int recPid: 0
    property bool stopping: false

    function dir() {
        const music = Quickshell.env("XDG_MUSIC_DIR") || ((Quickshell.env("HOME") || "/tmp") + "/Music");
        return music + "/Voice Recorder";
    }
    function stamp() { return Qt.formatDateTime(new Date(), "yyyy-MM-dd hh-mm-ss"); }

    function start() {
        if (recording || !available)
            return;
        error = "";
        stopping = false;
        seconds = 0;
        level = 0;
        file = dir() + "/Voice Recorder " + stamp() + ".opus";
        // pw-record in the background of a shell that only waits: the pid
        // is printed first so pause/resume/stop can signal pw-record
        // itself (SIGSTOP freezes the capture, SIGINT finalises the file)
        rec.command = ["sh", "-c", 'mkdir -p "$1" || exit 1; pw-record --rate 48000 --channels 1 --format opus "$2" 2>/dev/null & rp=$!; echo "pid $rp"; wait $rp', "sh", dir(), file];
        state = "recording";
        rec.running = true;
        analyser.running = true;
    }
    function stop() {
        if (!recording)
            return;
        stopping = true;
        state = "idle";
        level = 0;
        analyser.running = false;
        if (recPid > 0)
            Quickshell.execDetached(["kill", "-INT", String(recPid)]);
        else if (rec.running)
            rec.signal(2);
    }
    function pause() {
        if (state !== "recording" || recPid <= 0)
            return;
        Quickshell.execDetached(["kill", "-STOP", String(recPid)]);
        state = "paused";
        level = 0;
    }
    function resume() {
        if (state !== "paused" || recPid <= 0)
            return;
        Quickshell.execDetached(["kill", "-CONT", String(recPid)]);
        state = "recording";
    }
    function togglePause() { state === "paused" ? resume() : pause(); }
    function toggle() { recording ? stop() : start(); }

    Process {
        id: rec
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("pid "))
                    root.recPid = parseInt(line.slice(4)) || 0;
            }
        }
        onExited: (code, status) => {
            const wasStopping = root.stopping;
            root.recPid = 0;
            root.stopping = false;
            root.level = 0;
            analyser.running = false;
            if (root.state !== "idle")
                root.state = "idle";
            root.refresh();
            if (wasStopping) {
                root.last = root.file;
                Quickshell.execDetached(["notify-send", "-a", "Voice Recorder", "-i", "media-record", "Recording saved", root.file.split("/").pop()]);
            } else if (code !== 0) {
                root.error = "recording failed";
                Quickshell.execDetached(["notify-send", "-a", "Voice Recorder", "-i", "media-record", "Recording failed", root.file]);
            }
        }
    }

    // the input level: a second pw-record, f32 on stdout, peak per 100 ms
    // printed by Python (no new deps: python3 is what Dictation already
    // runs). Lines are only honoured while actually recording, so a
    // paused recorder shows a flat meter, not the room.
    Process {
        id: analyser
        command: ["sh", "-c", 'pw-record --rate 48000 --channels 1 --format f32 - 2>/dev/null | python3 -u -c \'import sys, struct
buf = b""
peak = 0.0
n = 0
while True:
    chunk = sys.stdin.buffer.read(4096)
    if not chunk:
        break
    m = len(chunk) // 4 * 4
    for (v,) in struct.iter_unpack(\"<f\", chunk[:m]):
        if abs(v) > peak:
            peak = abs(v)
    n += m // 4
    if n >= 4800:
        print(\"%.4f\" % peak, flush=True)
        peak = 0.0
        n = 0\'', "sh"]
        stdout: SplitParser {
            onRead: line => {
                const v = parseFloat(line);
                if (isFinite(v) && root.state === "recording")
                    root.level = Math.max(0, Math.min(1, v));
            }
        }
    }

    Timer {
        interval: 1000
        running: root.state === "recording"
        repeat: true
        onTriggered: root.seconds++
    }

    // ---- the list: every .opus in the folder, newest first ----------------
    function refresh() { scan.running = true; }
    function whenOf(path) {
        try {
            const m = /(\d{4}-\d{2}-\d{2}) (\d{2}-\d{2}-\d{2})\.opus$/.exec(path.split("/").pop() || "");
            return m ? m[1] + " " + m[2].replace(/-/g, ":") : "";
        } catch (e) { return ""; }
    }
    Process {
        id: scan
        command: ["sh", "-c", 'd="$1"; [ -d "$d" ] || exit 0; ls -t "$d"/*.opus 2>/dev/null | head -100', "sh", root.dir()]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                text.split("\n").forEach(p => { if (p.trim()) out.push({ path: p, name: p.split("/").pop(), when: root.whenOf(p) }); });
                root.recordings = out;
            }
        }
    }

    // ---- rename (keeps the .opus extension), delete (gio trash), play -----
    function cleanName(name) {
        let n = String(name || "").trim().replace(/\//g, "");
        if (!n)
            return "";
        return /\.opus$/i.test(n) ? n : n + ".opus";
    }
    function rename(path, name) {
        const to = cleanName(name);
        if (!path || !to || to === path.split("/").pop())
            return;
        renameProc.command = ["gio", "rename", "--", path, to];
        renameProc.running = true;
        if (last === path)
            last = path.substring(0, path.lastIndexOf("/") + 1) + to;
    }
    Process { id: renameProc; onExited: root.refresh() }

    function trash(path) {
        if (!path)
            return;
        trashProc.command = ["gio", "trash", "--", path];
        trashProc.running = true;
        if (last === path)
            last = "";
    }
    Process { id: trashProc; onExited: root.refresh() }

    function play(path) {
        if (!path)
            return;
        lastPlayed = path;
        const p = Media.current;
        const uri = path.startsWith("file://") ? path : "file://" + encodeURI(path);
        if (p && p.openUri)
            p.openUri(uri);
        else
            Quickshell.execDetached(["xdg-open", path]);
    }

    // ---- Monologue-style take trim ---------------------------------------
    // Two offsets on the take itself, cut through the Trim service's audio
    // branch (ffmpeg re-encodes libopus, no -c copy) as *.trimmed.opus
    // beside the original.
    property string trimFile: ""            // the take being trimmed, "" when none
    property real trimStart: 0
    property real trimEnd: 0
    property real trimDuration: 0           // ffprobe seconds for the take
    property string trimmedLast: ""         // the *.trimmed.opus written
    property string trimError: ""
    function trimmedPathFor(p) {
        return (p || "").replace(/\.opus$/i, "") + ".trimmed.opus";   // *.trimmed.opus beside the original
    }
    function openTrim(path) {
        trimFile = path || "";
        trimStart = 0;
        trimEnd = 0;
        trimDuration = 0;
        trimmedLast = "";
        trimError = "";
        if (trimFile)
            VideoTrimmer.setInput(trimFile);
    }
    function setTrimStart(v) {
        v = parseFloat(v);
        if (!isFinite(v))
            return;
        trimStart = Math.max(0, v);
        if (trimDuration > 0)
            trimStart = Math.min(trimStart, trimDuration);
        if (trimEnd > 0 && trimStart >= trimEnd)
            trimStart = Math.max(0, trimEnd - 0.1);
    }
    function setTrimEnd(v) {
        v = parseFloat(v);
        if (!isFinite(v))
            return;
        v = Math.max(trimStart + 0.1, v);
        if (trimDuration > 0)
            v = Math.min(v, trimDuration);
        trimEnd = v;
    }
    function saveTrimmedCopy() {
        if (!trimFile || VideoTrimmer.cutting)
            return;
        const out = trimmedPathFor(trimFile);
        const s = trimStart, e = trimDuration > 0 && trimEnd <= 0 ? trimDuration : trimEnd;
        if (e <= s) {
            trimError = Tr.t("End must be after start");
            return;
        }
        trimError = "";
        trimmedLast = "";
        VideoTrimmer.trimAudio(trimFile, s, e);
        // trimmedLast is set on Trim's completion (Connections below);
        // the output name is deterministic, so the check there suffices.
    }
    Connections {
        target: VideoTrimmer
        function onResultChanged() {
            if (VideoTrimmer.result && VideoTrimmer.result === root.trimmedPathFor(root.trimFile))
                root.trimmedLast = VideoTrimmer.result;
        }
        function onInputDurationChanged() {
            if (VideoTrimmer.input === root.trimFile) {
                root.trimDuration = VideoTrimmer.inputDuration;
                if (root.trimEnd <= 0 && VideoTrimmer.inputDuration > 0)
                    root.trimEnd = VideoTrimmer.inputDuration;
            }
        }
        function onErrorChanged() {
            if (VideoTrimmer.error)
                root.trimError = VideoTrimmer.error;
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v pw-record"]
        onExited: code => root.available = code === 0
    }
    Component.onCompleted: refresh()
}
