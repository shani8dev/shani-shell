pragma Singleton
// Other cities' clocks on the control centre's calendar (Settings > Date &
// language picks the zones). Read where the kernel keeps them — /usr/share/
// zoneinfo via `date`, so DST just works — and refreshed every 30 s only while
// a surface that shows the clocks is open and a city is chosen; once all of
// them are closed (or none is chosen), no process is spawned.
//
// Alarms live in Settings.alarms ({ time "HH:MM", label, days?, enabled? }:
// optional weekday repeat and on/off); the check is minute-granular, so it
// wakes on the minute boundary like Automations and Focus, not on a fixed poll.
// They ring once through notify-send, the same path snooze and the focus timer
// use.
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

    // same shape as SysStats.wanted: polling is only worth a `date` process per
    // zone while a clock surface is actually visible
    readonly property bool wanted: Settings.loaded
        && Settings.data.worldClocks.length > 0
        && (Array.from(Settings.data.desktopWidgets).indexOf("clocks") >= 0
            || Settings.data.barWorldClock || Ui.clocks || Ui.calendar || Ui.controlCenter)
    onWantedChanged: if (wanted) root.refresh()

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
        running: root.wanted
        repeat: true
        triggeredOnStart: true
        onTriggered: read.running = root.wanted
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
        if (root.wanted) read.running = true;
    }

    // ---- alarms -------------------------------------------------------------
    // Settings.data.alarms holds { time "HH:MM", label, days?, enabled? }.
    // days is JS weekday numbers (0=Sun .. 6=Sat); missing/empty means every
    // day and missing enabled means on, so old {time,label} records still fire.
    readonly property var alarms: Settings.data.alarms
    property var lastFired: ""             // the minute it last rang, so it rings once
    function alarmDays(a) {
        return (a && Array.isArray(a.days) && a.days.length) ? a.days.map(Number) : [0, 1, 2, 3, 4, 5, 6];
    }
    function alarmFiresOn(a, date) {
        return !!a && a.enabled !== false && alarmDays(a).indexOf(date.getDay()) >= 0;
    }
    function addAlarm(time, label, days, enabled) {
        const t = String(time || "").trim();
        if (!/^([01]?\d|2[0-3]):[0-5]\d$/.test(t))
            return false;
        const rec = { time: t.padStart(5, "0"), label: String(label || "").trim() || t.padStart(5, "0"), enabled: enabled !== false };
        if (Array.isArray(days) && days.length)
            rec.days = days.map(Number).filter(d => d >= 0 && d <= 6);
        const list = Array.from(Settings.data.alarms || []);
        list.push(rec);
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
    function ring(summary, body) {
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Alarms", "-i", "alarm-symbolic", "-h", "string:sound-name:alarm-clock-elapsed", summary, body]);
    }
    function checkAlarms() {
        if (!Settings.loaded) return;
        const now = Qt.formatTime(new Date(), "HH:mm");
        if (now === lastFired) return;
        const today = new Date();
        const hits = (Settings.data.alarms || []).filter(a => a.time === now && alarmFiresOn(a, today));
        if (hits.length === 0) return;
        lastFired = now;
        for (const hit of hits)
            ring("⏰ " + (hit.label || hit.time), Tr.t("Alarm for %1", now));
    }

    // Snooze re-notifies through the same notify-send path. The list is in
    // memory only (like the stopwatch) and the timer runs while one is pending.
    property var snoozes: []
    function snooze(label, minutes) {
        const m = Math.max(1, Math.round(Number(minutes) || 9));
        const list = Array.from(root.snoozes || []);
        list.push({ at: Date.now() + m * 60000, label: String(label || "") });
        root.snoozes = list;
        snoozeTick.restart();
    }
    function checkSnoozes() {
        if (!root.snoozes || root.snoozes.length === 0) return;
        const now = Date.now();
        const due = root.snoozes.filter(s => s.at <= now);
        if (due.length === 0) return;
        root.snoozes = root.snoozes.filter(s => s.at > now);
        for (const s of due)
            ring(Tr.t("Snoozed alarm"), s.label || Tr.t("Alarm"));
        if (root.snoozes.length === 0) snoozeTick.stop();
    }
    Timer {
        id: snoozeTick
        interval: 30000
        repeat: true
        onTriggered: root.checkSnoozes()
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
