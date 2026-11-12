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
        // *.trimmed.opus beside the original for takes, *.trimmed.mp4 for video
        if (isAudio(p))
            return p.replace(/\.opus$/i, "") + ".trimmed.opus";
        return p.replace(/\.[^.\/]+$/, "") + ".trimmed.mp4";
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

    // ---- the cut ------------------------------------------------------------
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
        if (audio) {
            // no -c copy for opus seek: re-encode libopus
            cutProc.command = ["ffmpeg", "-y", "-loglevel", "error", "-ss", String(start), "-to", String(end), "-i", input, "-c:a", "libopus", out];
        } else {
            // the cut: stream copy, out.mp4
            cutProc.command = ["ffmpeg", "-y", "-loglevel", "error", "-ss", String(start), "-to", String(end), "-i", input, "-c", "copy", out];
        }
        cutProc.running = true;
    }
    function trimAudio(path, s, e) {
        if (!path)
            return;
        setInput(path);
        setStart(s);
        setEnd(e);
        if (end <= start && inputDuration > 0)
            setEnd(inputDuration);
        cut();
        return outputFor(path);
    }
    function cutAudio(path, s, e) { return trimAudio(path, s, e); }

    Process {
        id: cutProc
        property string out: ""
        property bool audio: false
        property bool fellBack: false
        onExited: code => {
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
