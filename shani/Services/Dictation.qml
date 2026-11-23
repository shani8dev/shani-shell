pragma Singleton
// Voice typing for the screen keyboard's mic key: record from the default
// microphone (PipeWire), transcribe with Chronoa's own speech engine in the
// keyboard's language (bridge/dictate.py), and type the words into the
// focused field through the same virtual-keyboard path as the keys.
// Tap to start, tap to stop.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string phase: "idle"        // idle | recording | transcribing
    property string last: ""             // the last transcript (for `state`)
    property string error: ""
    property int secondsLeft: 0          // recording countdown, for a listening chip
    readonly property string wav: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-dictation.wav"
    readonly property string tool: Quickshell.env("SHANI_DICTATE_TOOL") || "/usr/lib/shani-shell/dictate.py"

    // the language the keyboard shows: "en", "mr", or an xkb layout's ISO code
    function lang() {
        if (Osk.lang === "en" || Osk.lang === "mr")
            return Osk.lang;
        const l = Osk.current && Osk.current.langs ? Osk.current.langs[0] : "";
        return l || "auto";
    }
    function toggle() {
        if (phase === "recording")
            rec.signal(2);
        else if (phase === "idle")
            start();
    }
    function start() {
        error = "";
        if (Audio.micMuted) {
            error = Tr.t("Unmute the microphone first");
            Quickshell.execDetached(["notify-send", "-a", Tr.t("Voice typing"), "-i", "audio-input-microphone", error]);
            return;
        }
        secondsLeft = 60;
        phase = "recording";
        rec.running = true;
    }
    // Raw speech must not outlive the transcription (or a cancelled run).
    function dropWav() {
        Quickshell.execDetached(["rm", "-f", "--", root.wav]);
    }

    // the countdown a listening chip can show; bounded by the same 60 s as rec
    Timer {
        interval: 1000
        repeat: true
        running: root.phase === "recording"
        onTriggered: root.secondsLeft = Math.max(0, root.secondsLeft - 1)
    }

    Process {
        id: rec
        command: ["timeout", "--preserve-status", "-s", "INT", "60", "pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", root.wav]
        onExited: (code, status) => {
            root.secondsLeft = 0;
            if (root.phase !== "recording") {
                root.dropWav();     // cancelled: no STT will read the file
                return;
            }
            if (code !== 0) {
                // denied/busy/missing mic: never transcribe a stale or empty WAV
                root.dropWav();
                root.phase = "idle";
                root.error = Tr.t("Could not record — check the microphone");
                Quickshell.execDetached(["notify-send", "-a", Tr.t("Voice typing"), "-i", "audio-input-microphone", root.error]);
                return;
            }
            root.phase = "transcribing";
            stt.command = ["python3", root.tool, root.lang(), root.wav];
            stt.running = true;
        }
    }
    Process {
        id: stt
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                root.last = t;
                if (t !== "")
                    Quickshell.execDetached(["wtype", "--", t + " "]);
            }
        }
        stderr: StdioCollector { onStreamFinished: root.error = text.trim().split("\n").pop() || "" }
        onExited: code => {
            root.dropWav();
            root.phase = "idle";
            if (code !== 0)
                Quickshell.execDetached(["notify-send", "-a", "Voice typing", "-i", "audio-input-microphone", "Could not transcribe", root.error]);
        }
    }
}
