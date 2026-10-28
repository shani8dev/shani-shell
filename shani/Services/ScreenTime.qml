pragma Singleton
// Screen time (after Android's Digital Wellbeing): how long each app had the
// focus, today and over the week — from niri's focus events, counted only
// while you are there (not idle, not locked). Kept in Quickshell's state
// directory, on this machine only.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var days: ({})             // "YYYY-MM-DD" -> { app: seconds }
    readonly property string today: Qt.formatDate(clock.date, "yyyy-MM-dd")
    readonly property var todayByApp: days[today] || {}
    readonly property int todayTotal: Object.values(todayByApp).reduce((a, b) => a + b, 0)
    readonly property var top: Object.entries(todayByApp).sort((a, b) => b[1] - a[1]).slice(0, 6)
        .map(e => ({ app: e[0], seconds: e[1] }))
    property bool loaded: false

    function label(s) {
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }
    function appName(id) {
        const e = DesktopEntries.heuristicLookup(id);
        return e ? e.name : id;
    }

    // every 15 s, the focused app gets the time since the last tick
    Timer {
        interval: 15000
        running: Settings.data.screenTime && root.loaded
        repeat: true
        onTriggered: {
            const w = Niri.focusedWindow;
            if (!w || Lock.locked || Idle.dimmed)
                return;
            const app = root.appName(w.app_id || "unknown");
            const d = Object.assign({}, root.days);
            const t = Object.assign({}, d[root.today] || {});
            t[app] = (t[app] || 0) + 15;
            d[root.today] = t;
            // keep five weeks
            for (const k of Object.keys(d).sort().slice(0, -35))
                delete d[k];
            root.days = d;
            file.setText(JSON.stringify(d));
        }
    }
    FileView {
        id: file
        path: Quickshell.statePath("screen-time.json")
        printErrors: false
        onLoaded: { try { root.days = JSON.parse(text()); } catch (e) {} root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
}
