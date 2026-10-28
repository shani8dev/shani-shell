pragma Singleton
// Voice typing for the screen keyboard's mic key: record from the default
// microphone (PipeWire), transcribe with Chronoa's own speech engine in the
// keyboard's language (bridge/dictate.py), and type the words into the
// focused field through the same virtual-keyboard path as the keys.
// Tap to start, tap to stop.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property string phase: "idle"        // idle | recording | transcribing
    property string last: ""             // the last transcript (for `state`)
    property string error: ""
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
        phase = "recording";
        rec.running = true;
    }

    Process {
        id: rec
        command: ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", root.wav]
        onExited: (code, status) => {
            if (root.phase !== "recording")
                return;
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
            root.phase = "idle";
            if (code !== 0)
                Quickshell.execDetached(["notify-send", "-a", "Voice typing", "-i", "audio-input-microphone", "Could not transcribe", root.error]);
        }
    }
}
