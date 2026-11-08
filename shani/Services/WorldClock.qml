pragma Singleton
// Other cities' clocks on the control centre's calendar (Settings > Date &
// language picks the zones). Read where the kernel keeps them — /usr/share/
// zoneinfo via `date`, so DST just works — and refreshed every 30 s only while
// any city is chosen; none chosen, nothing runs.
//
// Alarms live in Settings.alarms ({ time "HH:MM", label }; the check is
// minute-granular, so it wakes on the minute boundary like Automations and
// Focus, not on a fixed poll) and ring once through notify-send, the same
// path the focus timer rings through.
//
// The stopwatch (start / pause / reset / laps) is the sidebar's, and
// counts in the foreground only while it is running.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var clocks: []   // [{ zone, city, time }]

    Process {
        id: read
        // "$@" is the zones; the leading "" is $0 (a shell -c argument, not a zone)
        command: ["sh", "-c", 'for z in "$@"; do echo "$z / $(TZ=$z date "+%a %H:%M")"; done', ""].concat(Array.from(Settings.data.worldClocks || []))
        stdout: StdioCollector {
            onStreamFinished: {
                root.clocks = text.trim().split("\n").filter(l => l).map(l => {
                    const z = l.split(" / ")[0];
                    return { zone: z, city: z.split("/").pop().replace(/_/g, " "), time: l.split(" / ")[1] || "" };
                });
            }
        }
    }
    Timer {
        interval: 30000
        running: Settings.loaded && Settings.data.worldClocks.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: read.running = Settings.data.worldClocks.length > 0
    }
    // settings load after us (or the person picks a city now)
    Connections {
        target: Settings
        function onLoadedChanged() { root.refresh(); }
    }
    Connections {
        target: Settings.data
        function onWorldClocksChanged() { root.refresh(); }
    }
    function refresh() {
        if (Settings.loaded && Settings.data.worldClocks.length > 0)
            read.running = true;
    }

    // ---- alarms -------------------------------------------------------------
    // [{ time "HH:MM", label }] in Settings; each rings once for its minute,
    // with the same critical notify-send the focus timer uses
    readonly property var alarms: Settings.data.alarms
    property var lastFired: ""             // the minute it last rang, so it rings once
    function addAlarm(time, label) {
        const t = String(time || "").trim();
        if (!/^([01]?\d|2[0-3]):[0-5]\d$/.test(t))
            return false;
        const list = Array.from(Settings.data.alarms || []);
        list.push({ time: t.padStart(5, "0"), label: String(label || "").trim() || t.padStart(5, "0") });
        Settings.data.alarms = list;
        return true;
    }
    function removeAlarm(index) {
        const list = Array.from(Settings.data.alarms || []);
        if (index >= 0 && index < list.length) {
            list.splice(index, 1);
            Settings.data.alarms = list;
        }
    }
    function checkAlarms() {
        if (!Settings.loaded) return;
        const now = Qt.formatTime(new Date(), "HH:mm");
        const hit = Array.from(Settings.data.alarms || []).find(a => a.time === now);
        if (!hit || now === lastFired) return;
        lastFired = now;
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Alarms", "-i", "alarm-symbolic", "-h", "string:sound-name:alarm-clock-elapsed",
            "⏰ " + (hit.label || hit.time), "Alarm for " + now]);
    }
    // minute-granular (“HH:MM”), so like Automations and Focus the wake is
    // the minute boundary itself, re-armed for the next one
    function msToNextMinute() {
        const n = new Date();
        return Math.max(1000, 60000 - (n.getSeconds() * 1000 + n.getMilliseconds()) + 250);
    }
    Timer {
        id: alarmClock
        interval: 1000
        running: true
        repeat: false
        triggeredOnStart: true
        onTriggered: {
            root.checkAlarms();
            alarmClock.interval = root.msToNextMinute();
            alarmClock.restart();
        }
    }

    // ---- stopwatch ----------------------------------------------------------
    property bool swRunning: false
    property int swElapsed: 0              // ms, what the display shows
    property var swLaps: []                // ["MM:SS.cc", …] newest last
    property int swStartedAt: 0            // Date.now() when the running span began
    property int swAccum: 0                // ms banked across pause / resume
    function fmt(ms) {
        const cs = Math.floor(ms / 10) % 100;
        const s = Math.floor(ms / 1000) % 60;
        const m = Math.floor(ms / 60000) % 60;
        const h = Math.floor(ms / 3600000);
        return (h > 0 ? h + ":" : "") + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0") + "." + String(cs).padStart(2, "0");
    }
    readonly property string swDisplay: fmt(swElapsed)
    function swStart() {
        if (swRunning) return;
        swRunning = true;
        swStartedAt = Date.now();
        swTick.restart();
    }
    function swPause() {
        if (!swRunning) return;
        swAccum = swElapsed;
        swRunning = false;
        swTick.stop();
    }
    function swToggle() { swRunning ? swPause() : swStart(); }
    function swReset() { swPause(); swElapsed = 0; swAccum = 0; swLaps = []; }
    function swLap() {
        if (!swRunning) return;
        swLaps = swLaps.concat([swDisplay]);
        if (swLaps.length > 12)
            swLaps = swLaps.slice(swLaps.length - 12);
    }
    Timer {
        id: swTick
        interval: 47
        repeat: true
        onTriggered: root.swElapsed = root.swAccum + (Date.now() - root.swStartedAt)
    }
}
