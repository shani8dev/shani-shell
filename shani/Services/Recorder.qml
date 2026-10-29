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
    // what to record: the focused screen or a part chosen with slurp; sound
    // from the computer (the output's monitor), the microphone, or none
    readonly property string area: Settings.data.recordArea         // screen | region
    readonly property string sound: Settings.data.recordSound       // none | desktop | mic
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
        // the region is asked for first (slurp; Escape cancels), the sound
        // source is the output's monitor for the computer's own sound
        // stopping while the region is being chosen ends slurp too, not only this shell
        proc.command = ["sh", "-c", 'd="$1" out="$2" area="$3" sound="$4" f="$5"; mkdir -p "$d" || exit 1
            set -- wf-recorder -f "$f"
            if [ "$area" = region ]; then
                # slurp in the background, waited on: a stop while choosing ends it, not only this shell
                r="${XDG_RUNTIME_DIR:-/tmp}/shani-record-region"; slurp -d -b "#0b0d1288" -c "#7fd1c1ff" -w 2 > "$r" & sp=$!
                echo "slurp $sp"; wait $sp || exit 3
                g=$(cat "$r"); rm -f "$r"; [ -n "$g" ] || exit 3; set -- "$@" -g "$g"
            elif [ -n "$out" ]; then set -- "$@" -o "$out"; fi
            case "$sound" in desktop) set -- "$@" --audio="$(pactl get-default-sink).monitor" ;; mic) set -- "$@" --audio="$(pactl get-default-source)" ;; esac
            echo recording; exec "$@"', "sh", dir(), Niri.focusedOutput, area, sound, file];
        selecting = area === "region";
        proc.running = true;
    }
    // while a region is being chosen, stopping ends slurp itself: a signal to
    // the shell around it cannot be trusted to (an ignored SIGINT is inherited)
    property bool selecting: false
    property int slurpPid: 0
    function stop() {
        if (!proc.running)
            return;
        if (selecting && slurpPid > 0)
            Quickshell.execDetached(["kill", String(slurpPid)]);
        else
            proc.signal(2);
    }
    function toggle() {
        recording ? stop() : start();
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("slurp "))
                    root.slurpPid = parseInt(line.slice(6)) || 0;
                else if (line === "recording") {
                    root.selecting = false;
                    root.slurpPid = 0;
                }
            }
        }
        onExited: (code, status) => {
            root.selecting = false;
            root.slurpPid = 0;
            if (code === 3)               // the region selection was cancelled: nothing to say
                return;
            Quickshell.execDetached(["notify-send", "-a", "Screen recorder", "-i", "media-record",
                code === 0 ? "Recording saved" : "Recording failed", root.file]);
        }
    }
    Timer {
        interval: 1000
        running: root.recording && !root.selecting
        repeat: true
        onTriggered: root.seconds++
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v wf-recorder"]
        onExited: code => root.available = code === 0
    }
}
