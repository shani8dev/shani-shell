pragma Singleton
// Video Trimmer, plus the
// audio branch for Voice Recorder takes. One ffmpeg path serves both:
//   video:  ffmpeg -ss START -to END -i IN -c copy OUT.mp4 (stream copy,
//           falling back to a libx264/aac re-encode when the copy fails —
//           a keyframe-exact cut is not always possible)
//   audio:  ffmpeg -ss START -to END -i IN -c:a libopus OUT.trimmed.opus
//           (opus is not frame-seekable for -c copy, so it is re-encoded)
// Durations come from ffprobe when it is present; without it the panel
// shows only filenames. Output sits beside the input.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property string input: ""              // video (or opus take) being trimmed
    property real inputDuration: 0         // ffprobe seconds, 0 = unknown
    readonly property real duration: inputDuration
    property real start: 0                 // start offset, seconds
    property real end: 0                   // end offset, seconds
    readonly property real selection: Math.max(0, end - start)
    readonly property real selectionDuration: Math.max(0, end - start)
    property string probePath: ""          // what inputDuration/resultDuration describe
    property string result: ""             // the file written by the last cut
    property string audioResult: ""        // same file, when the cut was audio
    property string videoResult: ""        // same file, when the cut was video
    readonly property string last: result
    property real resultDuration: -1       // ffprobe seconds, -1 = unknown
    property bool cutting: false
    property bool audioMode: false         // last cut took the opus branch
    property string error: ""
    property bool available: false         // ffmpeg is in the image
    property bool ffprobeAvailable: false

    // ---- frame stepping, a playhead and multiple segments ------------------
    readonly property real frameStep: 1 / 30
    property real playhead: 0              // where I / O / S act
    property var segments: []              // [{ start, end }] to join on export
    property real progress: 0              // 0..1, fed by ffmpeg's -progress
    property bool cancelled: false
    property string frameCaptured: ""      // the snapshot written by captureFrame
    property string captureError: ""
    readonly property string convertTool: Quickshell.env("SHANI_CONVERT_TOOL") || "/usr/lib/shani-shell/convert.py"

    signal trimmed(string path)

    function fmt(s) {
        const v = Math.max(0, s);
        const m = Math.floor(v / 60), sec = v - m * 60;
        return m + ":" + sec.toFixed(1).padStart(4, "0");
    }
    readonly property string inputDurationText: inputDuration > 0 ? fmt(inputDuration) : ""
    readonly property string selectionText: isFinite(start) && isFinite(end) && end > start
        ? fmt(start) + " – " + fmt(end) + " (" + fmt(selection) + ")" : ""

    function isAudio(p) { return /\.opus$/i.test(p || ""); }
    function isVideo(p) { return /\.(mp4|webm|mov|mkv|avi)$/i.test(p || ""); }
    function outputFor(p) {
        if (!p)
            return "";
        // A timestamp keeps a second cut from overwriting the first: ffmpeg
        // runs with -y, and an earlier `.trimmed` file was silent data loss.
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss");
        const base = isAudio(p) ? p.replace(/\.opus$/i, "") : p.replace(/\.[^.\/]+$/, "");
        return isAudio(p) ? base + ".trimmed-" + stamp + ".opus" : base + ".trimmed-" + stamp + ".mp4";
    }
    function videosDir() {
        return (Quickshell.env("XDG_VIDEOS_DIR") || (Quickshell.env("HOME") || "/tmp") + "/Videos") + "/Camera";
    }

    // ---- picking the input: a file, a folder's last video, or the default
    function open(path) {
        error = "";
        result = "";
        audioResult = "";
        videoResult = "";
        resultDuration = -1;
        start = 0;
        end = 0;
        if (!path) {
            pickFrom(videosDir());
            Ui.videoTrimmer = true;
            return;
        }
        if (isVideo(path) || isAudio(path)) {
            setInput(path);
        } else {
            pickFrom(path);
        }
        Ui.videoTrimmer = true;
    }
    function pickFrom(folder) {
        pickProc.folder = folder || videosDir();
        // the folder's last video, newest first
        pickProc.command = ["sh", "-c", 'd="$1"; [ -d "$d" ] || exit 0; ls -t "$d"/*.mp4 "$d"/*.webm "$d"/*.mov "$d"/*.mkv "$d"/*.avi 2>/dev/null | head -1', "sh", pickProc.folder];
        pickProc.running = true;
    }
    function setInput(path) {
        input = (path || "").trim();
        start = 0;
        end = 0;
        inputDuration = 0;
        probePath = "";
        error = "";
        if (input)
            probe(input, "input");
    }
    // probes the named file's duration; kind "input" fills inputDuration,
    // "result" fills resultDuration (the output's own length)
    function probe(path, kind) {
        if (!path || !ffprobeAvailable) {
            if (kind === "result")
                resultDuration = -1;
            return;
        }
        probeProc.target = path;
        probeProc.kind = kind || "input";
        probeProc.command = ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", "--", path];
        probeProc.running = true;
    }
    Process {
        id: probeProc
        property string target
        property string kind: "input"
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat((text || "").trim().split("\n")[0]);
                if (!isFinite(v) || v <= 0)
                    return;
                if (probeProc.kind === "result") {
                    root.resultDuration = v;
                } else {
                    root.inputDuration = v;
                    root.probePath = probeProc.target;
                    if (root.input === probeProc.target && root.end <= 0)
                        root.end = v;
                }
            }
        }
    }
    Process {
        id: pickProc
        property string folder: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const p = (text || "").trim().split("\n")[0];
                if (p && (root.isVideo(p) || root.isAudio(p)))
                    root.setInput(p);
                else
                    root.error = Tr.t("No video found in that folder");
            }
        }
    }

    // ---- offsets ----------------------------------------------------------
    function setStart(v) {
        v = parseFloat(v);
        if (!isFinite(v))
            return;
        v = Math.max(0, v);
        if (inputDuration > 0)
            v = Math.min(v, inputDuration);
        if (end > 0 && v >= end)
            v = Math.max(0, end - 0.1);
        start = v;
    }
    function setEnd(v) {
        v = parseFloat(v);
        if (!isFinite(v))
            return;
        v = Math.max(start + 0.1, v);
        if (inputDuration > 0)
            v = Math.min(v, inputDuration);
        end = v;
    }
    function nudgeStart(d) { setStart(start + d); }
    function nudgeEnd(d) { setEnd(end + d); }

    // ---- the playhead: I marks in, O marks out, S splits at it --------------
    function setPlayhead(v) {
        v = parseFloat(v);
        if (!isFinite(v)) return;
        v = Math.max(0, v);
        if (inputDuration > 0) v = Math.min(v, inputDuration);
        playhead = v;
    }
    function nudgePlayhead(d) { setPlayhead(playhead + d); }
    function markIn() { setStart(playhead); }
    function markOut() { setEnd(playhead); }
    function addSegment(s, e) {
        s = parseFloat(s); e = parseFloat(e);
        if (!isFinite(s) || !isFinite(e) || e <= s) return false;
        if (inputDuration > 0) { s = Math.max(0, s); e = Math.min(e, inputDuration); }
        if (e <= s) return false;
        const m = segments.slice();
        m.push({ start: s, end: e });
        segments = m;
        return true;
    }
    function removeSegment(i) {
        if (i < 0 || i >= segments.length) return;
        const m = segments.slice();
        m.splice(i, 1);
        segments = m;
    }
    function clearSegments() { segments = []; }
    // S: with no segments yet, split the whole clip at the playhead; otherwise
    // split the last segment in two.
    function splitAtPlayhead() {
        if (inputDuration <= 0 || playhead <= 0 || playhead >= inputDuration) return;
        if (segments.length === 0) {
            addSegment(0, playhead);
            addSegment(playhead, inputDuration);
            return;
        }
        const last = segments[segments.length - 1];
        if (playhead <= last.start + 0.1 || playhead >= last.end - 0.1) return;
        const m = segments.slice();
        m.pop();
        m.push({ start: last.start, end: playhead }, { start: playhead, end: last.end });
        segments = m;
    }
    // a still of the frame at the playhead, into ~/Pictures/Camera
    function captureFrame(at) {
        const t = at === undefined ? playhead : parseFloat(at);
        if (!input || !isFinite(t)) return;
        const dir = (Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") || "/tmp") + "/Pictures") + "/Camera";
        const name = input.split("/").pop().replace(/\.[^.]+$/, "");
        const out = dir + "/" + name + " " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh-mm-ss") + ".png";
        capProc.command = ["sh", "-c", 'mkdir -p "${1%/*}" && ffmpeg -nostdin -loglevel error -ss "$2" -i "$3" -frames:v 1 "$1" && printf %s "$1"',
                           "sh", out, Math.max(0, t).toFixed(3), input];
        capProc.running = true;
    }
    Process {
        id: capProc
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p) { root.frameCaptured = p; root.captureError = ""; }
            }
        }
        onExited: code => { if (code !== 0) root.captureError = Tr.t("Could not capture the frame"); }
    }

    // ---- the cut ------------------------------------------------------------
    // cancel a running cut (or a segment join): drop the half-written file
    function cancelCut() {
        if (!cutting) return;
        cancelled = true;
        progress = 0;
        if (segProc.running) segProc.signal(2);
        else cutProc.signal(2);
    }
    function cut() {
        if (!input || cutting)
            return;
        if (end <= start) {
            error = Tr.t("End must be after start");
            return;
        }
        const audio = isAudio(input);
        audioMode = audio;
        error = "";
        result = "";
        audioResult = "";
        videoResult = "";
        resultDuration = -1;
        const out = outputFor(input);
        cutting = true;
        cutProc.out = out;
        cutProc.audio = audio;
        cutProc.fellBack = false;
        progress = 0;
        if (audio) {
            // no -c copy for opus seek: re-encode libopus
            cutProc.command = ["ffmpeg", "-y", "-loglevel", "error", "-ss", String(start), "-to", String(end), "-i", input, "-c:a", "libopus", "-progress", "pipe:1", "-nostats", out];
        } else {
            // the cut: stream copy, out.mp4
            cutProc.command = ["ffmpeg", "-y", "-loglevel", "error", "-ss", String(start), "-to", String(end), "-i", input, "-c", "copy", "-progress", "pipe:1", "-nostats", out];
        }
        cutProc.running = true;
        return out;   // the exact path used, so callers can match the later result
    }
    function trimAudio(path, s, e) {
        if (!path)
            return "";
        setInput(path);
        setStart(s);
        setEnd(e);
        if (end <= start && inputDuration > 0)
            setEnd(inputDuration);
        // cut() stamps the name; returning a fresh outputFor() here would
        // give a different timestamp than the file ffmpeg actually writes.
        return cut();
    }
    function cutAudio(path, s, e) { return trimAudio(path, s, e); }

    Process {
        id: cutProc
        property string out: ""
        property bool audio: false
        property bool fellBack: false
        stdout: SplitParser {
            onRead: line => {
                const m = /out_time_us=(\d+)/.exec(line);
                if (m && root.inputDuration > 0)
                    root.progress = Math.min(1, parseInt(m[1]) / 1e6 / root.inputDuration);
            }
        }
        onExited: code => {
            if (root.cancelled) {
                root.cancelled = false;
                root.cutting = false;
                root.progress = 0;
                root.error = Tr.t("Cut cancelled");
                if (root.cutProc.out)
                    Quickshell.execDetached(["rm", "-f", "--", root.cutProc.out]);
                return;
            }
            if (code === 0) {
                root.cutting = false;
                root.result = root.cutProc.out;
                if (root.cutProc.audio)
                    root.audioResult = root.cutProc.out;
                else
                    root.videoResult = root.cutProc.out;
                root.error = "";
                root.probe(root.cutProc.out, "result");
                root.trimmed(root.cutProc.out);
                Quickshell.execDetached(["notify-send", "-a", "Trim", "-i", "media-record",
                    root.cutProc.audio ? "Trimmed take saved" : "Cut saved", root.cutProc.out.split("/").pop()]);
            } else if (!root.cutProc.audio && !root.cutProc.fellBack) {
                // stream copy failed (unaligned keyframes): re-encode
                root.cutProc.fellBack = true;
                const out = root.cutProc.out;
                root.cutProc.command = ["ffmpeg", "-y", "-loglevel", "error", "-ss", String(root.start), "-to", String(root.end), "-i", root.input, "-c:v", "libx264", "-crf", "23", "-preset", "medium", "-c:a", "aac", "-movflags", "+faststart", out];
                root.cutProc.running = true;
            } else {
                root.cutting = false;
                root.error = Tr.t("Could not cut the video");
                Quickshell.execDetached(["notify-send", "-a", "Trim", "-i", "media-record", "Could not cut the video", root.input]);
            }
        }
    }

    // ---- multiple segments: cut each one and join them via convert.py -------
    function cutSegments() {
        if (cutting || segments.length < 2)
            return;
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss");
        const base = input.replace(/\.[^.\/]+$/, "");
        const out = base + ".segments-" + stamp + ".mp4";
        const args = [];
        for (const s of segments)
            args.push(String(s.start), String(s.end));
        segProc.command = ["python3", convertTool, "segments", input, out].concat(args);
        segProc.out = out;
        error = "";
        result = "";
        progress = 0;
        cancelled = false;
        cutting = true;
        segProc.running = true;
    }
    Process {
        id: segProc
        property string out: ""
        stdout: SplitParser {
            onRead: line => {
                let c = null;
                try { c = JSON.parse(line); } catch (e) { return; }
                if (c.progress !== undefined)
                    root.progress = c.progress;
                else if (c.done) {
                    root.result = c.done;
                    root.videoResult = c.done;
                    root.cutting = false;
                    root.progress = 1;
                    root.probe(c.done, "result");
                    root.trimmed(c.done);
                } else if (c.error) {
                    root.cutting = false;
                    root.error = c.error;
                }
            }
        }
        onExited: code => {
            if (root.cancelled) {
                root.cancelled = false;
                root.cutting = false;
                root.progress = 0;
                root.error = Tr.t("Cut cancelled");
                if (root.segProc.out)
                    Quickshell.execDetached(["rm", "-f", "--", root.segProc.out]);
            } else if (code !== 0 && !root.result) {
                root.cutting = false;
                root.error = Tr.t("Could not join the segments");
            }
        }
    }

    // ---- result actions -------------------------------------------------------
    function openResult() {
        if (!result)
            return;
        const p = Media.current;
        const uri = result.startsWith("file://") ? result : "file://" + encodeURI(result);
        if (p && p.openUri)
            p.openUri(uri);
        else
            Quickshell.execDetached(["xdg-open", result]);
    }
    function trashResult() {
        if (!result)
            return;
        trashProc.command = ["gio", "trash", "--", result];
        trashProc.running = true;
    }
    Process {
        id: trashProc
        onExited: {
            const doomed = root.result;
            root.result = "";
            root.audioResult = "";
            root.videoResult = "";
            root.resultDuration = -1;
            if (doomed)
                root.trimmed(doomed);
        }
    }

    function close() { Ui.videoTrimmer = false; }

    Process {
        running: true
        command: ["sh", "-c", "command -v ffmpeg"]
        onExited: code => root.available = code === 0
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v ffprobe"]
        onExited: code => root.ffprobeAvailable = code === 0
    }
    Component.onCompleted: pickProc.folder = videosDir()
}
