pragma Singleton
// Screen recording with wf-recorder over wlr-screencopy (which niri advertises).
// Stops with SIGINT so the file is finalised; the bar shows a red dot + timer.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property bool recording: proc.running
    property string file: ""
    property int seconds: 0
    property bool withAudio: false
    readonly property string elapsed: Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    property bool available: false

    function dir() {
        return Settings.data.recordingsDir || ((Quickshell.env("XDG_VIDEOS_DIR") || (Quickshell.env("HOME") + "/Videos")) + "/Recordings");
    }
    function start() {
        if (recording || !available)
            return;
        const stamp = new Date().toISOString().slice(0, 19).replace(/[T:]/g, "-");
        file = dir() + "/Recording-" + stamp + ".mp4";
        seconds = 0;
        const args = ["wf-recorder", "-f", file];
        if (Niri.focusedOutput !== "")
            args.push("-o", Niri.focusedOutput);
        if (withAudio)
            args.push("--audio");
        proc.command = ["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", dir(), ...args];
        proc.running = true;
    }
    function stop() {
        if (recording)
            proc.signal(2);
    }
    function toggle() {
        recording ? stop() : start();
    }

    Process {
        id: proc
        onExited: (code, status) => {
            Quickshell.execDetached(["notify-send", "-a", "Screen recorder", "-i", "media-record",
                code === 0 ? "Recording saved" : "Recording failed", root.file]);
        }
    }
    Timer {
        interval: 1000
        running: root.recording
        repeat: true
        onTriggered: root.seconds++
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v wf-recorder"]
        onExited: code => root.available = code === 0
    }
}
