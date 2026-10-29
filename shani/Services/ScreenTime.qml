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
            root.streak += 15;
            root.wellbeing();
        }
    }

    // Wellbeing (Settings > Notifications): a daily limit, and a reminder to
    // look away after a stretch at the screen. Both are told, never enforced.
    property int streak: 0                // seconds at the screen without a break
    property string limitToldFor: ""      // the day the limit was last told
    property int breaksTold: 0            // for the tests
    // a pause - idle (dimmed) or locked - is a break: the stretch starts again
    Connections { target: Idle; function onDimmedChanged() { if (Idle.dimmed) root.streak = 0; } }
    Connections { target: Lock; function onLockedChanged() { if (Lock.locked) root.streak = 0; } }
    function wellbeing() {
        const d = Settings.data;
        if (d.breakEveryMinutes > 0 && root.streak >= d.breakEveryMinutes * 60) {
            root.streak = 0;
            root.breaksTold++;
            Quickshell.execDetached(["notify-send", "-a", "Wellbeing", "-i", "preferences-desktop-screensaver",
                Tr.t("Time for a break"), Tr.t("%1 at the screen. Look at something far away for a moment, and stretch.", root.label(d.breakEveryMinutes * 60))]);
        }
        if (d.screenLimitMinutes > 0 && root.todayTotal >= d.screenLimitMinutes * 60 && root.limitToldFor !== root.today) {
            root.limitToldFor = root.today;
            Quickshell.execDetached(["notify-send", "-a", "Wellbeing", "-u", "critical", "-i", "appointment-soon",
                Tr.t("Today's screen time is up"), Tr.t("You set %1 a day. It is only a reminder — carry on if you need to.", root.label(d.screenLimitMinutes * 60))]);
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
