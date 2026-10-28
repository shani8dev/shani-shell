pragma Singleton
// Focus modes (after macOS / Android): a named profile that holds back
// notifications except from the apps it allows, and can keep the screen awake
// or warm it. Chosen by hand, or by its schedule — a hand choice wins until
// it is turned off. Critical notifications always come through.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var modes: Settings.data.focusModes
    property string scheduled: ""       // the mode whose schedule covers now
    readonly property string active: Settings.data.focusMode !== "" ? Settings.data.focusMode : scheduled
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
        return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
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

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.evaluate()
    }
}
