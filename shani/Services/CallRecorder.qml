pragma Singleton
// Call recording: your microphone and what the speakers play, mixed into one
// file (~/Recordings/Calls) — for any call app. It reminds you to tell the
// other side: recording a call without consent is unlawful in many places.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property bool recording: rec.running
    property string file: ""
    property int seconds: 0
    readonly property string elapsed: Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")

    function toggle() { recording ? stop() : start(); }
    function start() {
        const dir = (Quickshell.env("HOME") || "/tmp") + "/Recordings/Calls";
        file = dir + "/Call-" + new Date().toISOString().slice(0, 19).replace(/[T:]/g, "-") + ".ogg";
        seconds = 0;
        rec.command = ["sh", "-c", 'mkdir -p "$1"; sink=$(pactl get-default-sink); exec ffmpeg -loglevel error -f pulse -i default -f pulse -i "$sink.monitor" -filter_complex amix=inputs=2:duration=longest -c:a libopus -b:a 48k "$2"',
                       "sh", dir, file];
        rec.running = true;
        Quickshell.execDetached(["notify-send", "-a", "Call recording", "-i", "media-record", "Recording the call",
            "Let the other side know — recording without consent is unlawful in many places."]);
    }
    function stop() {
        if (rec.running)
            rec.signal(2);
    }

    Process {
        id: rec
        onExited: Quickshell.execDetached(["notify-send", "-a", "Call recording", "-i", "media-record", "Call saved", root.file])
    }
    Timer { interval: 1000; running: root.recording; repeat: true; onTriggered: root.seconds++ }
}
