pragma Singleton
// Focus modes (after macOS / Android): a named profile that holds back
// notifications except from the apps it allows, and can keep the screen awake
// or warm it. Chosen by hand, or by its schedule — a hand choice wins until
// it is turned off. Critical notifications always come through.
import Quickshell
import QtQuick
import qs.Common
import "../Common/Format.js" as Format

Singleton {
    id: root
    readonly property var modes: Settings.data.focusModes
    property string scheduled: ""       // the mode whose schedule covers now
    // a hand choice wins until turned off - unless that mode was deleted or
    // renamed in Settings: a dangling name must not disable every schedule
    readonly property string active: {
        const manual = Settings.data.focusMode;
        return manual && modes.some(m => m.name === manual) ? manual : scheduled;
    }
    readonly property var mode: modes.find(m => m.name === active) || null
    readonly property bool on: mode !== null
    readonly property bool nightLight: on && !!mode.nightLight
    readonly property bool caffeine: on && !!mode.caffeine

    function set(name) {
        Settings.data.focusMode = Settings.data.focusMode === name ? "" : name;
    }
    function allows(appName) {
        return !on || (mode.allow || []).some(a => a.toLowerCase() === (appName || "").toLowerCase());
    }
    function minutes(hhmm) {
        const m = (hhmm || "").match(/^(\d{1,2}):(\d{2})$/);
        if (!m) return -1;
        const h = Number(m[1]), min = Number(m[2]);
        if (h > 23 || min > 59) return -1;   // "25:70" made a window cover all day, or none
        return h * 60 + min;
    }
    function inSchedule(sc, now) {
        if (!sc || !sc.on)
            return false;
        const from = minutes(sc.from), to = minutes(sc.to);
        if (from < 0 || to < 0)
            return false;
        const t = now.getHours() * 60 + now.getMinutes();
        // a window past midnight belongs to the day it started
        const day = (t < to && to < from) ? (now.getDay() + 6) % 7 : now.getDay();
        if ((sc.days || []).indexOf(day) < 0)
            return false;
        return from <= to ? (t >= from && t < to) : (t >= from || t < to);
    }
    function evaluate() {
        const now = new Date();
        const m = modes.find(x => inSchedule(x.schedule, now));
        scheduled = m ? m.name : "";
    }
    onModesChanged: evaluate()

    // schedules are minute-granular (from/to are "HH:MM"), so evaluate at
    // each minute boundary instead of every 30 s: the wake is the clock
    // itself, re-armed for the next boundary. A changed schedule is
    // evaluated at once (onModesChanged above).
    function msToNextMinute() { return Format.msToNextMinute(); }
    Timer {
        id: clock
        interval: 1000
        running: true
        repeat: false
        triggeredOnStart: true
        onTriggered: {
            root.evaluate();
            clock.interval = root.msToNextMinute();
            clock.restart();
        }
    }
}
