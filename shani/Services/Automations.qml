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
import "../Common/Format.js" as Format

Singleton {
    id: root
    readonly property var rules: Settings.data.automations
    property var fired: []              // last 50 firings: { at, rule }, for the tests
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
        case "open": Launch.app(a); break;
        // bound arbitrary user commands so a hang cannot wedge the shell
        case "run": Quickshell.execDetached(["timeout", "10s", "sh", "-c", a]); break;
        default: return;
        }
        // keep a bounded, timestamped record instead of growing forever
        fired = fired.concat([{ at: new Date().toISOString(), rule: r.when + "=" + r.is + " → " + r.then + " " + a }]).slice(-50);
    }
    // Two rules that share a trigger (when/is) and an action target (then)
    // would write the same setting in array order — last write wins. Treat
    // them as one conflict group; only the first of a group actually fires.
    function conflictKey(r) {
        return String(r.when || "") + "|" + String(r.is || "").trim() + "|" + String(r.then || "");
    }
    function conflictsAt(i) {
        const list = Array.from(rules || []);
        const r = list[i];
        if (!r || r.on === false) return false;
        const key = conflictKey(r);
        return list.some((x, j) => j !== i && x.on !== false && conflictKey(x) === key);
    }
    function check() {
        if (!Settings.loaded) return;
        const seen = {};
        const firedKeys = {};
        Array.from(rules).forEach((r, i) => {
            const now = r.on !== false && holds(r);
            if (now && !wasTrue[i]) {
                const key = conflictKey(r);
                if (!firedKeys[key]) { act(r); firedKeys[key] = true; }
            }
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
    // time rules are minute-granular ("HH:MM"), so the clock wakes once per
    // minute, aligned to the minute boundary — not every 15 s. Each wake
    // sets timeNow (flipping rules at their minute) and re-arms itself for
    // the next boundary. The other triggers already became events above
    // (wifi / power / output / displays change signals).
    function msToNextMinute() { return Format.msToNextMinute(); }
    Timer {
        id: clock
        interval: 1000
        running: true
        repeat: false
        triggeredOnStart: true
        onTriggered: {
            root.timeNow = Qt.formatTime(new Date(), "HH:mm");
            clock.interval = root.msToNextMinute();
            clock.restart();
        }
    }
}
