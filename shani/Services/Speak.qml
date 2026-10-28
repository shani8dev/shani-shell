pragma Singleton
// Select to speak (after Android / ChromeOS): the selected text — or any text
// given — read aloud by speech-dispatcher, the engine Orca uses; espeak-ng
// when speech-dispatcher is not there.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property bool speaking: say.running
    property string last: ""

    function speak(text) {
        text = (text || "").trim();
        if (text === "")
            return;
        say.running = false;
        last = text.slice(0, 2000);
        // what was being said is cut off first, in the same command: a separate
        // detached cancel could land after this starts and silence it
        // speed: spd-say's rate is -100..100, espeak-ng's words per minute
        const rate = { slow: ["-40", "130"], normal: ["0", "175"], fast: ["45", "240"] }[Settings.data.speechRate] || ["0", "175"];
        say.command = ["sh", "-c", 'if command -v spd-say >/dev/null; then spd-say -C; exec spd-say -w -r "$2" -- "$1"; else pkill -x espeak-ng; exec espeak-ng -s "$3" -- "$1"; fi', "sh", last, rate[0], rate[1]];
        say.running = true;
    }
    function speakSelection() { grab.running = true; }
    function stop() {
        say.running = false;
        Quickshell.execDetached(["sh", "-c", "spd-say -S 2>/dev/null; pkill -x espeak-ng 2>/dev/null; true"]);
    }

    Process { id: say }

    // speak notifications (after Windows Narrator / Android TalkBack): what came
    // in, read aloud — the app and the title, not the body
    Connections {
        target: Notifs
        function onAlerted(n) {
            if (Settings.data.speakNotifications)
                root.speak((n.appName ? n.appName + ": " : "") + (n.summary || ""));
        }
    }
    // the primary selection: what is highlighted right now, in any app
    Process {
        id: grab
        command: ["wl-paste", "--primary", "--no-newline"]
        stdout: StdioCollector { onStreamFinished: root.speak(text) }
    }
}
