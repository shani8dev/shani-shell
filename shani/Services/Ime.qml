pragma Singleton
// fcitx5: typing in other scripts — Devanagari phonetic ("namaste" ->
// नमस्ते, m17n hi-itrans / hi-phonetic), Inscript, and the rest of m17n's
// tables. It speaks niri's input-method-v2 directly (its waylandim frontend).
// The bar shows the active method; the screen keyboard takes the same
// protocol slot, so Osk hands it over and back.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
    function stop() { Quickshell.execDetached(["fcitx5-remote", "-e"]); root.current = ""; root.running = false; recheck.restart(); }
    function start() { Quickshell.execDetached(["fcitx5", "-d", "--replace"]); recheck.restart(); }

    Process {
        id: query
        // fcitx5-remote answers nothing (and fails) when fcitx5 is not running
        command: ["fcitx5-remote", "-n"]
        stdout: StdioCollector {
            id: queryOut
            onStreamFinished: {
                root.current = text.trim();
                root.running = root.current !== "";
            }
        }
        onExited: {
            // stdout only updates on success; with no answer fcitx5 has died,
            // so drop the stale method label and running state here
            if (!queryOut.text.trim()) {
                root.current = "";
                root.running = false;
            }
        }
    }
    // How many input methods there are to switch between, from fcitx5's own
    // profile (watched, not polled). With one - the keyboard layout alone, as
    // for most people - the method cannot change, so it is asked once; with
    // two or more it is asked every 2 s (fcitx5-remote has no watch mode, and
    // Ctrl+Space switches inside fcitx5 without telling anyone).
    property int methods: 0
    property int _userMethods: -1                // -1: no readable user profile
    property int _systemMethods: -1
    function countMethods(t) { return (t.match(/^\[Groups\/\d+\/Items\/\d+\]/mg) || []).length; }
    // fcitx5 prefers the user profile, falling back to the system one; keep
    // both counts so one view's load-failure cannot zero out the other's result
    function updateMethods() {
        root.methods = _userMethods >= 0 ? _userMethods : (_systemMethods >= 0 ? _systemMethods : 0);
    }
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/fcitx5/profile"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root._userMethods = root.countMethods(text()); root.updateMethods(); query.running = true; }
        onLoadFailed: { root._userMethods = -1; root.updateMethods(); }
    }
    FileView {
        // fresh installs ship the two-method profile here, not in ~/.config;
        // watch it too or the 2 s poll never starts until fcitx5 writes a copy
        path: (Quickshell.env("XDG_CONFIG_DIRS") || "/etc/xdg").split(":")[0] + "/fcitx5/profile"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root._systemMethods = root.countMethods(text()); root.updateMethods(); query.running = true; }
        onLoadFailed: { root._systemMethods = -1; root.updateMethods(); }
    }
    // ...but only while someone is typing: the method changes by a key (Ctrl+Space),
    // so after 20 s with no input it cannot have changed, and the poll rests; the
    // next key wakes it, asking at once. (ShaniOS ships two methods, English and
    // Hindi phonetic: every install had a fcitx5-remote every 2 s, all day.)
    IdleMonitor {
        id: typing
        timeout: 20
        respectInhibitors: false
    }
    Timer {
        id: poll
        interval: 2000
        running: root.available && root.methods > 1 && !typing.isIdle
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
