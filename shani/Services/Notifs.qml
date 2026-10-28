pragma Singleton
// The notification daemon (org.freedesktop.Notifications) and its history.
// Every notification is kept until dismissed (the control center lists it);
// popups are a separate, short-lived view of new ones, suppressed by Do Not
// Disturb except for critical urgency.
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values.slice().reverse()
    readonly property int count: list.length
    property var popups: []          // newest last
    // a notification that was let through: flash alerts and speak notifications follow it
    signal alerted(var n)
    // a sound for each notification that comes through (the freedesktop theme;
    // critical ones get the alarm); silenced apps and DND never alert, so never sound
    property int sounds: 0
    onAlerted: n => {
        if (!Settings.data.notifSound)
            return;
        const crit = n.urgency === NotificationUrgency.Critical;
        sounds++;
        Quickshell.execDetached(["sh", "-c", 'for f in "$@"; do [ -f "$f" ] && exec pw-play "$f"; done',
            "sh", "/usr/share/sounds/freedesktop/stereo/" + (crit ? "dialog-warning.oga" : "message.oga"),
            "/usr/share/sounds/freedesktop/stereo/message.oga"]);
    }
    // when each arrived, by id, for "5 min" on the cards
    property var arrived: ({})
    readonly property bool dnd: Settings.data.doNotDisturb
    // automatic quiet: presenting (the screen is shared) or something fullscreen
    readonly property bool presenting: Settings.data.quietWhileSharing && Audio.screenShared
    readonly property bool quiet: presenting || GameMode.fullscreen

    function setDnd(on) {
        Settings.data.doNotDisturb = on;
    }
    // snooze (after Android): the notification goes now and comes back later,
    // re-posted with what it said; kept in the state dir, so a restart keeps it
    property var snoozed: []             // [{ due, app, summary, body, icon }]
    function snooze(n, minutes) {
        snoozed = snoozed.concat([{ due: Date.now() + minutes * 60000, app: n.appName || "", summary: n.summary || "",
                                    body: n.body || "", icon: n.appIcon || "" }]);
        snoozeFile.setText(JSON.stringify(snoozed));
        n.dismiss();
    }
    Timer {
        interval: 20000
        running: root.snoozed.length > 0
        repeat: true
        onTriggered: {
            const now = Date.now();
            const due = root.snoozed.filter(x => x.due <= now);
            if (!due.length)
                return;
            root.snoozed = root.snoozed.filter(x => x.due > now);
            snoozeFile.setText(JSON.stringify(root.snoozed));
            for (const x of due)
                Quickshell.execDetached(["notify-send", "-a", x.app, "-i", x.icon || "preferences-system-notifications", x.summary, x.body]);
        }
    }
    FileView {
        id: snoozeFile
        path: Quickshell.statePath("snoozed.json")
        printErrors: false
        onLoaded: { try { root.snoozed = JSON.parse(text()); } catch (e) {} }
    }

    // a summary by Chronoa (after iOS / macOS): what came in, in a few lines
    function summarize() {
        const items = list.slice(0, 30).map(n => "- " + (n.appName || "App") + ": " + n.summary + (n.body ? " — " + n.body.replace(/<[^>]*>/g, "").slice(0, 200) : ""));
        if (items.length)
            Chronoa.ask("Summarise these notifications for me in a few lines — what needs me, what can wait:\n" + items.join("\n"));
    }

    function clearAll() {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        popups = [];
    }
    function dropPopup(n) {
        popups = popups.filter(p => p !== n);
        if (n && n.transient && n.tracked)
            n.expire();
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true

        onNotification: n => {
            n.tracked = true;
            root.arrived[n.id] = Date.now();
            const app = n.appName || "";
            if (app && Array.from(Settings.data.notifApps).indexOf(app) < 0)
                Settings.data.notifApps = Array.from(Settings.data.notifApps).concat([app]).slice(-40);
            // an app with pop-ups off: the sidebar only. DND holds everything
            // back but the apps allowed through it; a focus mode, all but the apps
            // it allows; critical urgency always comes through
            const silent = Array.from(Settings.data.silentApps).indexOf(app) >= 0;
            const throughDnd = Array.from(Settings.data.dndAllowedApps).indexOf(app) >= 0;
            if (n.urgency === NotificationUrgency.Critical
                || (!silent && !root.quiet && (root.dnd ? throughDnd : Focus.allows(app))))
            {
                root.popups = root.popups.concat([n]).slice(-4);
                root.alerted(n);
            }
            n.closed.connect(() => root.popups = root.popups.filter(p => p !== n));
        }
    }
}
