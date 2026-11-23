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
    // `clock` is declared at the foot of this file, so at start-up the binding is
    // evaluated before it exists: reading clock.date then assigned undefined to a
    // string ("Unable to assign [undefined] to QString", and shell-ends-clean
    // FAILs on exactly that). The guard is the fix, not a workaround: until the
    // clock is up, the system's own date is the same answer.
    readonly property string today: clock ? Qt.formatDate(clock.date, "yyyy-MM-dd") : Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property var todayByApp: days[today] || {}
    readonly property int todayTotal: Object.values(todayByApp).reduce((a, b) => a + b, 0)
    readonly property var top: Object.entries(todayByApp).sort((a, b) => b[1] - a[1]).slice(0, 6)
        .map(e => ({ app: e[0], seconds: e[1] }))
    property bool loaded: false

    function label(s) {
        let m = Math.round(s / 60), h = Math.floor(m / 60);
        m -= h * 60;   // rounding 59m30s up must carry into the hour, not print "1 h 60 min"
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }
    function appName(id) {
        const e = DesktopEntries.heuristicLookup(id);
        return e ? e.name : id;
    }

    // every 15 s, the focused app gets the time since the last tick
    property var lastTick: 0
    Timer {
        interval: 15000
        running: Settings.data.screenTime && root.loaded
        repeat: true
        onTriggered: {
            const now = Date.now();
            // count the time that actually passed, capped at one interval: a
            // late wake (load, suspend) must not invent it, nor drop it when early
            const secs = root.lastTick ? Math.round(Math.min(15000, now - root.lastTick) / 1000) : 15;
            root.lastTick = now;
            const w = Niri.focusedWindow;
            if (!w || Lock.locked || Idle.dimmed)
                return;
            const app = root.appName(w.app_id || "unknown");
            const d = Object.assign({}, root.days);
            const t = Object.assign({}, d[root.today] || {});
            t[app] = (t[app] || 0) + secs;
            d[root.today] = t;
            // keep five weeks of dates; the "already told" marker is not a day
            const dates = Object.keys(d).filter(k => /^\d{4}-\d{2}-\d{2}$/.test(k)).sort();
            for (const k of dates.slice(0, -35))
                delete d[k];
            root.days = d;
            file.setText(JSON.stringify(d));
            root.streak += secs;
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
            // persist the marker beside the days: a restart the same day must
            // not repeat a reminder the person has already been given
            const stored = Object.assign({}, root.days, { _told: root.today });
            root.days = stored;
            file.setText(JSON.stringify(stored));
            Quickshell.execDetached(["notify-send", "-a", "Wellbeing", "-u", "critical", "-i", "appointment-soon",
                Tr.t("Today's screen time is up"), Tr.t("You set %1 a day. It is only a reminder — carry on if you need to.", root.label(d.screenLimitMinutes * 60))]);
        }
    }
    FileView {
        id: file
        path: Quickshell.statePath("screen-time.json")
        printErrors: false
        onLoaded: {
            try {
                const stored = JSON.parse(text());
                root.days = stored && typeof stored === "object" && !Array.isArray(stored) ? stored : {};
                root.limitToldFor = stored && typeof stored._told === "string" ? stored._told : "";
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
}
