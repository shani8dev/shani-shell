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
    property var _perApp: ({})
    // Notification filtering rules (noctalia-inspired): applied before showing popups
    readonly property var rules: NotifsRules ? NotifsRules.rules : []

    function _filterNotification(appName, summary, body) {
        return NotifsRules ? NotifsRules.evaluate(appName, summary, body) : "";
    }
    // unread per app, for the dock's badges (Android's notification dots): what is
    // still in the list, keyed by the desktop entry the app named and by its name
    readonly property var perApp: _perApp
    function _rebuildPerApp() {
        const out = {};
        for (const n of list) {
            const keys = new Set([(n.desktopEntry || "").toLowerCase(), (n.appName || "").toLowerCase()]);
            for (const k of keys)
                if (k) out[k] = (out[k] || 0) + 1;
        }
        _perApp = out;
    }
    onListChanged: { _rebuildPerApp(); root.saveSoon(); }
    Component.onCompleted: _rebuildPerApp()
    function countFor(entry, id) {
        const keys = [id, entry && entry.id, entry && entry.name, entry && entry.startupClass].filter(Boolean).map(k => k.toLowerCase());
        for (const k of keys)
            if (perApp[k]) return perApp[k];
        return 0;
    }
    property var popups: []          // newest last
    // an incoming call from any app (Chronoa's phone over Bluetooth, a VoIP app):
    // the freedesktop "call.incoming" category, newest first; the Island carries it
    readonly property var incomingCall: list.find(n => n.hints && n.hints["category"] === "call.incoming") || null
    function answerCall() { act(incomingCall, /answer|accept|pick/i); }
    function declineCall() { if (!act(incomingCall, /decline|reject|hang/i) && incomingCall) incomingCall.dismiss(); }
    // the notification's own action: isolation prevents unrelated apps from
    // requesting attention when actions or close signals fire
    function act(n, re) {
        if (!n) return false;
        const a = Array.from(n.actions || []).find(x => re.test(x.identifier) || re.test(x.text));
        if (a && n.id) a.invoke({ notificationId: n.id, appName: n.appName || "" });
        else if (a) a.invoke();
        return !!a;
    }
    // a notification that was let through: flash alerts and speak notifications follow it
    signal alerted(var n)
    // a sound for each notification that comes through (the freedesktop theme;
    // critical ones get the alarm); silenced apps and DND never alert, so never sound
    property int sounds: 0
    property string lastSound: ""      // the file the last alert played (the tests)
    onAlerted: n => {
        if (!Settings.data.notifSound)
            return;
        if (Settings.data.soundNotification === false)
            return;
        // the app's own say first (the spec's hints): no sound at all, a sound
        // file, or a theme sound by name; else ours by urgency
        const h = n.hints || {};
        if (h["suppress-sound"])
            return;
        const crit = n.urgency === NotificationUrgency.Critical;
        const dir = "/usr/share/sounds/freedesktop/stereo/";
        const own = h["sound-file"] ? String(h["sound-file"]) : h["sound-name"] ? dir + h["sound-name"] + ".oga" : "";
        sounds++;
        lastSound = own || dir + (crit ? "dialog-warning.oga" : "message.oga");
        Quickshell.execDetached(["sh", "-c", 'for f in "$@"; do [ -f "$f" ] && exec pw-play "$f"; done',
            "sh", lastSound, dir + "message.oga"]);
    }
    // when each arrived, by id, for "5 min" on the cards
    property var arrived: ({})
    readonly property bool dnd: Settings.data.doNotDisturb
    property var lastDndWanted: null
    function minutes(s) { const m = /^(\d\d?):(\d\d)$/.exec(s || ""); return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : -1; }
    function wantDnd() {
        const from = minutes(Settings.data.dndFrom), to = minutes(Settings.data.dndTo);
        if (from < 0 || to < 0) return false;
        const now = new Date(), t = now.getHours() * 60 + now.getMinutes();
        return from < to ? t >= from && t < to : t >= from || t < to;
    }
    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: Settings.loaded && Settings.data.dndSchedule !== "manual"
        onTriggered: {
            const want = root.wantDnd();
            if (want !== root.lastDndWanted)
                Settings.data.doNotDisturb = want;
            root.lastDndWanted = want;
        }
        onRunningChanged: root.lastDndWanted = null
    }
    // automatic quiet: presenting (the screen is shared) or something fullscreen
    readonly property bool presenting: Settings.data.quietWhileSharing && Audio.screenShared
    readonly property bool quiet: presenting || GameMode.fullscreen

    function setDnd(on) {
        Settings.data.doNotDisturb = on;
        Settings.data.dndUntil = 0;
    }
    // on, and off again by itself at `ms` (an hour from now, the meeting's end, tomorrow 8:00)
    function setDndUntil(ms) {
        Settings.data.doNotDisturb = true;
        Settings.data.dndUntil = ms;
    }
    // the agenda's event happening now, if any: "until this meeting ends"
    readonly property var meetingNow: Agenda.events.find(e => !e.allDay && e.start * 1000 <= Date.now() && e.end * 1000 > Date.now()) || null
    function tomorrowMorning() {
        const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(8, 0, 0, 0);
        return d.getTime();
    }
    readonly property string dndUntilText: Settings.data.doNotDisturb && Settings.data.dndUntil > 0
        ? Tr.t("until %1", Qt.formatDateTime(new Date(Settings.data.dndUntil), Settings.data.use24h ? "HH:mm" : "h:mm AP")) : ""
    Timer {
        interval: 15000
        repeat: true
        running: Settings.loaded && Settings.data.doNotDisturb && Settings.data.dndUntil > 0
        triggeredOnStart: true
        onTriggered: if (Date.now() >= Settings.data.dndUntil) root.setDnd(false)
    }
    // snooze (after Android): the notification goes now and comes back later,
    // re-posted with what it said; kept in the state dir, so a restart keeps it
    property var snoozed: []             // [{ due, app, summary, body, icon }]
    function isSilenced(app) { return !!app && Array.from(Settings.data.silentApps).indexOf(app) >= 0; }
    function setSilenced(app, on) {
        const rest = Array.from(Settings.data.silentApps).filter(a => a !== app);
        Settings.data.silentApps = on ? rest.concat([app]) : rest;
    }
    function snooze(n, minutes) {
        snoozed = snoozed.concat([{ due: Date.now() + minutes * 60000, app: n.appName || "",
                                    notificationId: n.id || null, notificationApp: n.appName || "",
                                    summary: n.summary || "", body: n.body || "", icon: n.appIcon || "" }]);
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
        earlier = [];
    }

    // ---- kept across a restart: what was unread is written down (a summary, not the
    // live notification - its actions died with the app's request) and shown again,
    // under Earlier, until cleared. Dismissed ones leave the file with the list.
    property var earlier: []             // [{ app, summary, body, time }]
    property bool historyRead: false     // nothing is written before the old file is read
    function keyOf(app, summary) { return (app || "") + "\n" + (summary || ""); }
    function snapshot() {
        const live = list.map(n => ({ app: n.appName || "", summary: n.summary || "",
                                      body: (n.body || "").replace(/<[^>]*>/g, "").slice(0, 300),
                                      time: arrived[n.id] || Date.now() }))
            .filter(e => e.summary !== "");
        return live.concat(earlier).slice(0, 50);
    }
    function forgetEarlier(entry) { earlier = entry ? earlier.filter(e => e !== entry) : []; }
    onEarlierChanged: root.saveSoon()
    // within 1.5 s of the first change, not pushed back by every one after it:
    // a busy stream of notifications would otherwise keep it from ever writing
    function saveSoon() { if (historyRead && !saveHistory.running) saveHistory.start(); }
    Timer { id: saveHistory; interval: 1500; onTriggered: history.setText(JSON.stringify(root.snapshot())) }
    FileView {
        id: history
        path: Quickshell.statePath("notifications.json")
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                // still live (a reload keeps them): not shown twice
                const live = new Set(root.list.map(n => root.keyOf(n.appName, n.summary)));
                root.earlier = JSON.parse(text()).filter(e => e && e.summary && !live.has(root.keyOf(e.app, e.summary))).slice(0, 50);
            } catch (e) {}
            root.historyRead = true;
        }
        onLoadFailed: root.historyRead = true
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
        // the reply field ("inline-reply" action → NotificationReplied): Chronoa's phone texts, chat apps
        inlineReplySupported: true

        onNotification: n => {
            n.tracked = true;
            root.arrived[n.id] = Date.now();
            const app = n.appName || "";
            if (app && Array.from(Settings.data.notifApps).indexOf(app) < 0)
                Settings.data.notifApps = Array.from(Settings.data.notifApps).concat([app]).slice(-40);
            // an app with pop-ups off: the sidebar only. DND holds everything
            // back but the apps allowed through it; a focus mode, all but the apps
            // it allows; the lock screen holds them too when dndWhileLocked is on;
            // critical urgency always comes through
            const silent = Array.from(Settings.data.silentApps).indexOf(app) >= 0;
            const throughDnd = Array.from(Settings.data.dndAllowedApps).indexOf(app) >= 0;
            const lockedOut = Settings.data.dndWhileLocked && Lock.locked && !throughDnd;
            if (n.urgency === NotificationUrgency.Critical
                || (!silent && !root.quiet && !lockedOut && (root.dnd ? throughDnd : Focus.allows(app))))
            {
                root.popups = root.popups.concat([n]).slice(-4);
                root.alerted(n);
            }
            n.closed.connect(() => root.popups = root.popups.filter(p => p !== n));
        }
    }
}
