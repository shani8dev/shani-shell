pragma Singleton
// Other cities' clocks on the control centre's calendar (Settings > Date &
// language picks the zones). Read where the kernel keeps them — /usr/share/
// zoneinfo via `date`, so DST just works — and refreshed every 30 s only while
// a surface that shows the clocks is open and a city is chosen; once all of
// them are closed (or none is chosen), no process is spawned.
//
// Alarms live in Settings.alarms ({ time "HH:MM", label, days?, enabled?,
// group?, sound? }: optional weekday repeat, on/off, a named group and a
// sound-theme hint); the check is minute-granular, so it wakes on the minute
// boundary like Automations and Focus, not on a fixed poll. They ring once
// through notify-send, the same path snooze and the timers use.
//
// The stopwatch (start / pause / reset / laps) is the sidebar's, and
// counts in the foreground only while it is running. Laps keep a split time
// beside the cumulative one so the Clocks window can copy a useful report.
//
// The Clocks window can also add cities, convert a time between zones and run
// several named timers at once. Zone names are checked against the list from
// timedatectl before they reach a `date` command; timers are in memory only,
// like the stopwatch and snoozes, and ring through the same notification path.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/Format.js" as Format

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

    // ---- zone picker, shared with the Clocks window -------------------------
    // One cached list for the in-app search and the conversion helper. The
    // zone.tab fallback keeps a usable list where timedatectl is absent.
    property var zones: []
    property string zonesError: ""
    function refreshZones() { zoneList.running = false; zoneList.running = true; }
    Process {
        id: zoneList
        command: ["sh", "-c", 'timedatectl list-timezones 2>/dev/null || find /usr/share/zoneinfo -type f 2>/dev/null | sed "s#^/usr/share/zoneinfo/##"']
        stdout: StdioCollector {
            onStreamFinished: {
                const z = text.split("\n").map(s => s.trim()).filter(s => /^[A-Za-z_][A-Za-z_ +\-]*\/[A-Za-z_0-9+\-\/]+$/.test(s));
                root.zones = z;
                root.zonesError = z.length ? "" : Tr.t("Time zones unavailable — install tzdata");
            }
        }
    }
    Component.onCompleted: root.refreshZones()

    // the search is a plain substring on the canonical zone name, so a space
    // typed for "New York" finds America/New_York
    function matchingZones(query) {
        const q = String(query || "").trim().toLowerCase().replace(/ /g, "_");
        if (q.length < 2) return [];
        return (root.zones || []).filter(z => z.toLowerCase().indexOf(q) >= 0).slice(0, 8);
    }
    function addWorldClock(zone) {
        const z = String(zone || "").trim();
        // the allowlist is also the injection guard for the `date` loop above
        if (!z || (root.zones || []).indexOf(z) < 0) return false;
        const list = Array.from(Settings.data.worldClocks || []);
        if (list.indexOf(z) >= 0) return false;
        list.push(z);
        Settings.data.worldClocks = list;
        root.refresh();
        return true;
    }
    function removeWorldClock(zone) {
        const list = Array.from(Settings.data.worldClocks || []);
        const i = list.indexOf(zone);
        if (i < 0) return false;
        list.splice(i, 1);
        Settings.data.worldClocks = list;
        root.refresh();
        return true;
    }

    // ---- convert a wall-clock time between two zones -----------------------
    // `date` owns the DST rules; the zones come from the allowlist and the
    // time is HH:MM, so nothing typed reaches the shell unvalidated.
    property string convertResult: ""
    property string convertError: ""
    function convertZoneTime(fromZone, toZone, timeText) {
        root.convertResult = "";
        root.convertError = "";
        const f = String(fromZone || "").trim();
        const t = String(toZone || "").trim();
        const time = String(timeText || "").trim();
        if ((root.zones || []).indexOf(f) < 0 || (root.zones || []).indexOf(t) < 0
                || !/^([01]?\d|2[0-3]):[0-5]\d$/.test(time)) {
            root.convertError = Tr.t("Enter HH:MM and two time zones from the list");
            return false;
        }
        convertProc.command = ["sh", "-c", 'epoch=$(TZ="$1" date -d "$2" +%s 2>/dev/null) || { echo ERROR; exit 0; }; TZ="$3" date -d "@$epoch" "+%a %H:%M (%Z)"', "", f, time, t];
        convertProc.running = false;
        convertProc.running = true;
        return true;
    }
    Process {
        id: convertProc
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim();
                if (!s || s === "ERROR") {
                    root.convertResult = "";
                    root.convertError = Tr.t("That time could not be converted");
                } else {
                    root.convertResult = s;
                    root.convertError = "";
                }
            }
        }
    }

    // ---- alarms -------------------------------------------------------------
    // Settings.data.alarms holds { time "HH:MM", label, days?, enabled?,
    // group?, sound? }. days is JS weekday numbers (0=Sun .. 6=Sat);
    // missing/empty means every day, missing enabled means on and a missing
    // sound means the original alarm hint, so old {time,label} records still
    // fire unchanged.
    readonly property var alarms: Settings.data.alarms
    property string lastFired: ""          // the minute it last rang, so it rings once
    property var firedKeys: []             // which alarms rang in that minute
    // a key includes the record, so an alarm added *during* an already-fired
    // minute still rings instead of being swallowed by the single-minute guard
    function alarmKey(a, minute) {
        return minute + "|" + String(a.time || "") + "|" + String(a.label || "")
            + "|" + (Array.isArray(a.days) ? a.days.join(",") : "");
    }
    readonly property var groups: Array.from(new Set((Settings.data.alarms || [])
        .map(a => String((a && a.group) || "").trim()).filter(g => g))).sort()
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
    // Edit in place: adding a replacement would change the index the sidebar
    // is about to remove and drop the alarm's group.
    function updateAlarm(index, time, label, days, enabled) {
        const list = Array.from(Settings.data.alarms || []);
        if (index < 0 || index >= list.length) return false;
        const t = String(time || "").trim();
        if (!/^([01]?\d|2[0-3]):[0-5]\d$/.test(t)) return false;
        const rec = Object.assign({}, list[index], {
            time: t.padStart(5, "0"),
            label: String(label || "").trim() || t.padStart(5, "0"),
            enabled: enabled !== false
        });
        if (Array.isArray(days) && days.length) rec.days = days.map(Number).filter(d => d >= 0 && d <= 6);
        else delete rec.days;                 // no days selected means every day
        list[index] = rec;
        Settings.data.alarms = list;
        return true;
    }
    function setAlarmGroup(index, group) {
        const list = Array.from(Settings.data.alarms || []);
        if (index < 0 || index >= list.length) return false;
        const rec = Object.assign({}, list[index]);
        const g = String(group || "").trim();
        if (g) rec.group = g;
        else delete rec.group;
        list[index] = rec;
        Settings.data.alarms = list;
        return true;
    }
    // Only these canonical freedesktop sound-theme names ever reach notify-send
    // as `-h string:sound-name:<name>`. A persisted record is data, not code:
    // anything else falls back to the original hint, so no hint or option can
    // be injected into the detached command line.
    readonly property var alarmSounds: ["alarm-clock-elapsed", "alarm-clock", "bell", "chime", "default"]
    function validAlarmSound(name) {
        return root.alarmSounds.indexOf(String(name || "")) >= 0;
    }
    function alarmSound(name) {
        return root.validAlarmSound(name) ? String(name) : "alarm-clock-elapsed";
    }
    function setAlarmSound(index, sound) {
        const list = Array.from(Settings.data.alarms || []);
        if (index < 0 || index >= list.length || !root.validAlarmSound(sound)) return false;
        list[index] = Object.assign({}, list[index], { sound: root.alarmSound(sound) });
        Settings.data.alarms = list;
        return true;
    }
    // A quick rename in the alarm row: keep the time, days, group, sound and
    // enabled flag by editing the record in place instead of re-adding it.
    function setAlarmLabel(index, label) {
        const list = Array.from(Settings.data.alarms || []);
        if (index < 0 || index >= list.length) return false;
        const l = String(label || "").trim();
        if (!l) return false;
        list[index] = Object.assign({}, list[index], { label: l });
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
    function ring(summary, body, soundName) {
        const sound = root.alarmSound(soundName);
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Alarms", "-i", "alarm-symbolic", "-h", "string:sound-name:" + sound, summary, body]);
    }
    function checkAlarms() {
        if (!Settings.loaded) return;
        const now = Qt.formatTime(new Date(), "HH:mm");
        if (now !== root.lastFired) {
            root.lastFired = now;
            root.firedKeys = [];
        }
        const today = new Date();
        const keys = [];
        const hits = (Settings.data.alarms || []).filter(a => {
            if (a.time !== now || !alarmFiresOn(a, today)) return false;
            const key = root.alarmKey(a, now);
            if (root.firedKeys.indexOf(key) >= 0) return false;
            keys.push(key);
            return true;
        });
        if (hits.length === 0) return;
        root.firedKeys = root.firedKeys.concat(keys);
        for (const hit of hits)
            ring("⏰ " + (hit.label || hit.time), Tr.t("Alarm for %1", now), hit.sound);
    }

    // Snooze re-notifies through the same notify-send path. The list is in
    // memory only (like the stopwatch) and the timer runs while one is pending.
    property var snoozes: []
    function snooze(label, minutes) {
        // the Clocks window passes the group as an optional third argument;
        // the two-argument call from older surfaces still works
        const group = arguments.length > 2 ? arguments[2] : "";
        const m = Math.max(1, Math.round(Number(minutes) || 9));
        const list = Array.from(root.snoozes || []);
        list.push({ at: Date.now() + m * 60000, label: String(label || ""), minutes: m, group: String(group || "") });
        root.snoozes = list;
        snoozeTick.restart();
        return true;
    }
    function cancelSnooze(index) {
        const list = Array.from(root.snoozes || []);
        if (index < 0 || index >= list.length) return false;
        list.splice(index, 1);
        root.snoozes = list;
        if (list.length === 0) snoozeTick.stop();
        return true;
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
    function msToNextMinute() { return Format.msToNextMinute(); }
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

    // ---- extra timers -------------------------------------------------------
    // FocusTimer still drives the island countdown; these are the additional
    // named timers the Clocks window manages. One ticker serves all of them and
    // stops as soon as none is running.
    property var timers: []
    property int timerSeq: 0
    function addTimer(minutes, label) {
        const m = Math.round(Number(minutes));
        if (!(m >= 1 && m <= 600)) return false;
        const name = String(label || "").trim() || Tr.t("Timer %1 min").arg(m);
        const list = Array.from(root.timers || []);
        list.push({ id: ++root.timerSeq, label: name, total: m * 60000, left: m * 60000, running: true });
        root.timers = list;
        timerTick.start();
        return true;
    }
    function toggleTimer(index) {
        const list = Array.from(root.timers || []);
        if (index < 0 || index >= list.length) return false;
        const t = Object.assign({}, list[index]);
        t.running = !t.running;
        list[index] = t;
        root.timers = list;
        if (t.running) timerTick.start();
        else if (!list.some(x => x.running)) timerTick.stop();
        return true;
    }
    function restartTimer(index) {
        const list = Array.from(root.timers || []);
        if (index < 0 || index >= list.length) return false;
        list[index] = Object.assign({}, list[index], { left: list[index].total, running: true });
        root.timers = list;
        timerTick.start();
        return true;
    }
    function removeTimer(index) {
        const list = Array.from(root.timers || []);
        if (index < 0 || index >= list.length) return false;
        list.splice(index, 1);
        root.timers = list;
        if (!list.some(x => x.running)) timerTick.stop();
        return true;
    }
    function tickTimers() {
        const list = Array.from(root.timers || []);
        if (!list.length) { timerTick.stop(); return; }
        const done = [];
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            if (!t.running) continue;
            const left = Math.max(0, t.left - timerTick.interval);
            list[i] = Object.assign({}, t, { left: left, running: left > 0 });
            if (left === 0) done.push(t.label);
        }
        root.timers = list;
        for (const label of done) ring(Tr.t("Timer done"), label);
        if (!list.some(t => t.running)) timerTick.stop();
    }
    Timer { id: timerTick; interval: 1000; repeat: true; onTriggered: root.tickTimers() }

    // ---- stopwatch ----------------------------------------------------------
    property bool swRunning: false
    property int swElapsed: 0              // ms, what the display shows
    property var swLaps: []                // ["MM:SS.cc", …] newest last (the sidebar reads this)
    property var swLapDeltas: []           // ["+MM:SS.cc", …] split since the previous lap
    property var swLapTotals: []           // ms at each lap, so deltas stay exact
    property int swStartedAt: 0            // Date.now() when the running span began
    property int swAccum: 0                // ms banked across pause / resume
    function fmt(ms) {
        const cs = Math.floor(ms / 10) % 100;
        const s = Math.floor(ms / 1000) % 60;
        const m = Math.floor(ms / 60000) % 60;
        const h = Math.floor(ms / 3600000);
        return (h > 0 ? h + ":" : "") + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0") + "." + String(cs).padStart(2, "0");
    }
    function fmtDelta(ms) { return (ms < 0 ? "-" : "+") + fmt(Math.abs(ms)); }
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
    function swReset() { swPause(); swElapsed = 0; swAccum = 0; swLaps = []; swLapDeltas = []; swLapTotals = []; }
    function swLap() {
        if (!swRunning) return;
        const total = swElapsed;
        const previous = root.swLapTotals.length ? root.swLapTotals[root.swLapTotals.length - 1] : 0;
        root.swLapTotals = root.swLapTotals.concat([total]);
        root.swLapDeltas = root.swLapDeltas.concat([root.fmtDelta(total - previous)]);
        swLaps = swLaps.concat([swDisplay]);
        if (swLaps.length > 12) {
            swLaps = swLaps.slice(swLaps.length - 12);
            root.swLapDeltas = root.swLapDeltas.slice(root.swLapDeltas.length - 12);
            root.swLapTotals = root.swLapTotals.slice(root.swLapTotals.length - 12);
        }
    }
    function swExportText() {
        const lines = [Tr.t("Stopwatch laps"), Tr.t("Total %1").arg(root.fmt(root.swElapsed))];
        for (let i = 0; i < root.swLaps.length; i++)
            lines.push(String(i + 1) + ". " + root.swLaps[i] + " (" + root.swLapDeltas[i] + ")");
        return lines.join("\n");
    }
    Timer {
        id: swTick
        interval: 47
        repeat: true
        onTriggered: root.swElapsed = root.swAccum + (Date.now() - root.swStartedAt)
    }
}
