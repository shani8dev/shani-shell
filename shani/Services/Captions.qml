pragma Singleton
// Live captions (after Android / Windows): what the computer is playing,
// written out — recorded from the speakers in short chunks and transcribed by
// the same engine as voice typing (Chronoa's, via bridge/dictate.py). A few
// seconds behind: whisper has no true stream over system audio. Nothing is
// kept; each chunk is deleted once it is read.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool on: false
    // "speakers": live captions of what plays; "mic": live transcribe (after
    // Android) of the room — a conversation, a lecture — kept as a text file
    property string source: "speakers"
    readonly property string transcript: source === "mic"
        ? Quickshell.env("HOME") + "/Documents/Transcripts/" + Qt.formatDateTime(started, "yyyy-MM-dd hh-mm") + ".txt" : ""
    property date started: new Date()
    property var lines: []               // the last few captions
    readonly property string text: lines.join(" ")
    readonly property string tool: Dictation.tool

    function toggle() { start("speakers"); }
    function transcribe() { start("mic"); }
    function start(from) {
        const was = on && source === from;
        on = false;
        lines = [];
        source = from;
        started = new Date();
        // a tick later, so the recorder really stops and starts again with the new source
        if (!was)
            Qt.callLater(() => root.on = true);
    }

    Process {
        running: root.on
        // record 4 s of what the speakers play, hand it to transcription in the
        // background, record the next — prints one caption per chunk
        command: ["sh", "-c", 'd="${XDG_RUNTIME_DIR:-/tmp}/shani-captions"; mkdir -p "$d"; i=0
            while :; do
                f="$d/c$i.wav"
                timeout -s INT 4 pw-record -P "{ stream.capture.sink = $3 }" --rate 16000 --channels 1 --format s16 "$f" 2>/dev/null
                ( t=$(python3 "$1" "$2" "$f" 2>/dev/null); rm -f "$f"; [ -n "$t" ] && { echo "$t"; [ -n "$4" ] && { mkdir -p "${4%/*}"; echo "$t" >> "$4"; }; } ) &
                i=$(( (i + 1) % 8 ))
            done', "sh", root.tool, Settings.data.captionLanguage, String(root.source === "speakers"), root.transcript]
        stdout: SplitParser {
            onRead: line => root.lines = root.lines.concat([line.trim()]).slice(-3)
        }
    }
}
