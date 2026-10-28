pragma Singleton
// fcitx5: typing in other scripts — Devanagari phonetic ("namaste" ->
// नमस्ते, m17n hi-itrans / hi-phonetic), Inscript, and the rest of m17n's
// tables. It speaks niri's input-method-v2 directly (its waylandim frontend).
// The bar shows the active method; the screen keyboard takes the same
// protocol slot, so Osk hands it over and back.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool available: false
    property bool running: false
    property string current: ""          // fcitx5's name, e.g. keyboard-us, m17n_hi_itrans
    // what the bar shows: the script for m17n methods, the layout otherwise
    readonly property string label: {
        const m = current.match(/^m17n_([a-z]+)_/);
        if (m)
            return ({ hi: "हि", mr: "म", sa: "सं", ne: "ने", bn: "বা", ta: "த", te: "తె", kn: "ಕ", ml: "മ", gu: "ગુ", pa: "ਪੰ" })[m[1]] || m[1].toUpperCase();
        const k = current.match(/^keyboard-([a-z]+)/);
        return k ? k[1].toUpperCase() : "";
    }

    function toggle() { Quickshell.execDetached(["fcitx5-remote", "-t"]); poll.restart(); }
    function configure() { Quickshell.execDetached(["fcitx5-configtool"]); }
    function stop() { Quickshell.execDetached(["fcitx5-remote", "-e"]); }
    function start() { Quickshell.execDetached(["fcitx5", "-d", "--replace"]); }

    Process {
        id: query
        command: ["sh", "-c", "pgrep -x fcitx5 >/dev/null && fcitx5-remote -n"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.current = text.trim();
                root.running = root.current !== "";
            }
        }
    }
    // fcitx5-remote has no watch mode; a light query, and only while it runs
    Timer {
        id: poll
        interval: 1500
        running: root.available
        repeat: true
        triggeredOnStart: true
        onTriggered: query.running = true
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v fcitx5"]
        onExited: code => root.available = code === 0
    }
}
