pragma Singleton
// Automations (macOS Shortcuts' personal automations, Windows' "when this,
// do that" in Power Automate, KDE's activities rules): small rules kept in
// Settings.automations, each { when, is, then, arg, on }.
//
//   when  wifi (network name) · power ("battery" | "plugged") · output (the
//         sound output's name contains it, e.g. "headphones") · displays
//         (how many screens) · time ("HH:MM", every day)
//   then  focus (a focus mode, "" ends it) · dnd ("on" | "off") · volume
//         (percent) · style ("dark" | "light") · open (an app's desktop id)
//         · run (a shell command)
//
// A rule fires when its condition *becomes* true, not while it stays true:
// joining the office Wi-Fi turns Focus on once, and choosing otherwise by
// hand afterwards sticks.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var rules: Settings.data.automations
    property var fired: []              // "when=is → then arg", for the tests
    property var wasTrue: ({})          // rule index → condition last seen true

    readonly property string wifiNow: Net.activeWifi ? Net.activeWifi.name : ""
    readonly property string powerNow: Power.onBattery ? "battery" : "plugged"
    readonly property string outputNow: Audio.sink ? Audio.nodeName(Audio.sink) + " " + (Audio.sink.name || "") : ""
    readonly property int displaysNow: Displays.outputs.length
    property string timeNow: ""

    function holds(r) {
        const is = String(r.is || "").trim();
        switch (r.when) {
        case "wifi": return is !== "" && wifiNow === is;
        case "power": return powerNow === is;
        case "output": return is !== "" && outputNow.toLowerCase().indexOf(is.toLowerCase()) >= 0;
        case "displays": return displaysNow > 0 && displaysNow === parseInt(is);
        case "time": return timeNow === is.padStart(5, "0");
        }
        return false;
    }
    function act(r) {
        const a = String(r.arg || "");
        switch (r.then) {
        case "focus": Settings.data.focusMode = a; break;
        case "dnd": Settings.data.doNotDisturb = a !== "off"; break;
        case "volume": Audio.setVolume(Math.max(0, Math.min(100, parseInt(a) || 0)) / 100); break;
        case "style": Settings.data.darkMode = a === "dark"; break;
        case "open": Quickshell.execDetached(["gtk-launch", a]); break;
        case "run": Quickshell.execDetached(["sh", "-c", a]); break;
        default: return;
        }
        fired = fired.concat([r.when + "=" + r.is + " → " + r.then + " " + a]);
    }
    function check() {
        if (!Settings.loaded) return;
        const seen = {};
        Array.from(rules).forEach((r, i) => {
            const now = r.on !== false && holds(r);
            if (now && !wasTrue[i]) act(r);
            seen[i] = now;
        });
        wasTrue = seen;
    }
    // the first look only records what already holds, so starting the shell
    // on the office Wi-Fi does not undo what was chosen before a restart
    property bool primed: false
    function prime() {
        const seen = {};
        Array.from(rules).forEach((r, i) => seen[i] = r.on !== false && r.when !== "time" && holds(r));
        wasTrue = seen;
        primed = true;
    }
    onWifiNowChanged: if (primed) check()
    onPowerNowChanged: if (primed) check()
    onOutputNowChanged: if (primed) check()
    onDisplaysNowChanged: if (primed) check()
    onTimeNowChanged: if (primed) check()
    onRulesChanged: if (primed) prime()
    Timer {
        interval: 2000
        running: Settings.loaded && !root.primed
        onTriggered: root.prime()
    }
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.timeNow = Qt.formatTime(new Date(), "HH:mm")
    }
}
