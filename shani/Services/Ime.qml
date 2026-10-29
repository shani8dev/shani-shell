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

    function toggle() { Quickshell.execDetached(["fcitx5-remote", "-t"]); recheck.restart(); }
    Timer { id: recheck; interval: 800; onTriggered: query.running = true }   // fcitx5 needs a moment after a switch or a start
    function configure() { Quickshell.execDetached(["fcitx5-configtool"]); }
    function stop() { Quickshell.execDetached(["fcitx5-remote", "-e"]); recheck.restart(); }
    function start() { Quickshell.execDetached(["fcitx5", "-d", "--replace"]); recheck.restart(); }

    Process {
        id: query
        // fcitx5-remote answers nothing (and fails) when fcitx5 is not running
        command: ["fcitx5-remote", "-n"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.current = text.trim();
                root.running = root.current !== "";
            }
        }
    }
    // How many input methods there are to switch between, from fcitx5's own
    // profile (watched, not polled). With one - the keyboard layout alone, as
    // for most people - the method cannot change, so it is asked once; with
    // two or more it is asked every 2 s (fcitx5-remote has no watch mode, and
    // Ctrl+Space switches inside fcitx5 without telling anyone).
    property int methods: 0
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/fcitx5/profile"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.methods = (text().match(/^\[Groups\/\d+\/Items\/\d+\]/mg) || []).length; query.running = true; }
        onLoadFailed: root.methods = 0
    }
    Timer {
        id: poll
        interval: 2000
        running: root.available && root.methods > 1
        repeat: true
        triggeredOnStart: true
        onTriggered: query.running = true
    }
    onAvailableChanged: if (available) query.running = true
    // fcitx5 starting after the shell (both start at login; or restarted): asked
    // again while it is not running - soon, then less and less often
    Timer {
        id: waitStart
        interval: 1500
        running: root.available && !root.running && root.methods <= 1
        repeat: true
        onTriggered: { query.running = true; interval = Math.min(30000, interval * 2); }
        onRunningChanged: if (!running) interval = 1500
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v fcitx5"]
        onExited: code => root.available = code === 0
    }
}
