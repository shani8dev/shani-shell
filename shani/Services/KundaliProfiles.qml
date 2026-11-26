pragma Singleton
// Saved births, and what is ahead for them. A person saved in Kundali gets,
// unless they turn it off, a notification when a hard day is today or
// tomorrow (chandrashtama, an unfavourable tara) and when a dasha period
// begins or Saturn / Jupiter change sign - the indications a Kundali reader
// looks at first (bridge/kundali_forecast.py). Checked once a day from 07:00
// (and at sign-in after that); each notice is sent once.
//
// Birth details are personal: kept only on this computer, readable only by
// its owner, never sent anywhere.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    // [{ id, name, date, time, lat, lon, zone, place, alerts }]
    property var profiles: []
    property var outlook: ({})            // id -> the last forecast, for the window
    property var sent: ({})               // "id|date|what" -> true: a notice goes out once
    property string checkedOn: ""          // the day the morning check last ran
    readonly property string tool: Quickshell.env("SHANI_KUNDALI_FORECAST_TOOL") || "/usr/lib/shani-shell/kundali_forecast.py"
    readonly property string file: Quickshell.statePath("kundali-profiles.json")
    // the harness's stand-in for today (dev/session.sh): a fixed day to check against
    readonly property string todayOverride: Quickshell.env("SHANI_KUNDALI_TODAY") || ""
    function today() { return todayOverride || Qt.formatDate(new Date(), "yyyy-MM-dd"); }

    FileView {
        id: store
        path: root.file
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text()) || {};
                root.profiles = o.profiles || [];
                root.sent = o.sent || {};
                root.checkedOn = o.checkedOn || "";
            } catch (e) {}
        }
    }
    Timer {
        id: saveTimer
        interval: 600
        onTriggered: {
            store.setText(JSON.stringify({ profiles: root.profiles, sent: root.sent, checkedOn: root.checkedOn }));
            // only its owner may read it: birth dates and places are personal
            Quickshell.execDetached(["chmod", "600", root.file]);
        }
    }

    // ---- the saved births ----------------------------------------------------
    function birthArg(p) {
        if (p.zone) return p.date + "T" + (p.time || "12:00") + "@" + p.zone;
        const d = new Date(p.date + "T" + (p.time || "12:00") + ":00");
        return isNaN(d.getTime()) ? p.date + "T" + (p.time || "12:00") + ":00Z" : d.toISOString();
    }
    function same(a, b) { return a.date === b.date && a.time === b.time && Math.abs(a.lat - b.lat) < 1e-4 && Math.abs(a.lon - b.lon) < 1e-4; }
    function find(b) { return profiles.find(p => same(p, b)) || null; }
    // save a birth under a name; notices on unless the person says otherwise
    function save(b) {
        const list = profiles.filter(p => !same(p, b));
        const old = find(b);
        const p = { id: old ? old.id : String(Date.now()), name: b.name || Tr.t("Saved chart"), date: b.date, time: b.time,
                    lat: b.lat, lon: b.lon, zone: b.zone || "", place: b.place || "",
                    alerts: old ? old.alerts : (b.alerts === undefined ? true : !!b.alerts) };
        list.push(p);
        profiles = list;
        saveTimer.restart();
        check(true);
        return p;
    }
    function remove(id) {
        profiles = profiles.filter(p => p.id !== id);
        const o = Object.assign({}, outlook);
        delete o[id];
        outlook = o;
        saveTimer.restart();
    }
    function setAlerts(id, on) {
        profiles = profiles.map(p => p.id === id ? Object.assign({}, p, { alerts: on }) : p);
        saveTimer.restart();
    }

    // ---- the morning check -----------------------------------------------------
    property var queue: []
    function check(force) {
        const today = root.today();
        if (!force && (root.checkedOn === today || (!root.todayOverride && new Date().getHours() < 7))) return;
        if (!force) { root.checkedOn = today; saveTimer.restart(); }
        root.queue = root.profiles.slice();
        runNext();
    }
    function runNext() {
        if (forecaster.running || root.queue.length === 0) return;
        const p = root.queue[0];
        root.queue = root.queue.slice(1);
        forecaster.profile = p;
        forecaster.command = ["python3", root.tool, root.birthArg(p), String(p.lat), String(p.lon),
                              root.today(), "7"];
        forecaster.running = true;
    }
    Timer {
        interval: 20 * 60 * 1000
        running: root.profiles.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check(false)
    }
    Process {
        id: forecaster
        property var profile: null
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (!d.error && forecaster.profile) {
                        const o = Object.assign({}, root.outlook);
                        o[forecaster.profile.id] = d;
                        root.outlook = o;
                        if (forecaster.profile.alerts) root.notifyFor(forecaster.profile, d);
                    }
                } catch (e) {}
            }
        }
        onExited: Qt.callLater(root.runNext)
    }

    // ---- what reaches the person ---------------------------------------------------
    readonly property var taraNames: ({
        janma: Tr.t("Janma tara (the birth star): a day for care"),
        vipat: Tr.t("Vipat tara: obstacles"),
        pratyak: Tr.t("Pratyak tara: things go against you"),
        naidhana: Tr.t("Naidhana tara: the hardest of the stars")
    })
    function reasonText(r) {
        if (r.code === "chandrashtama") return Tr.t("The Moon is in the 8th sign from your birth Moon (chandrashtama)");
        if (r.code === "tara") return root.taraNames[r.tara] || r.tara;
        return r.code;
    }
    function changeText(c) {
        if (c.kind === "mahadasha") return Tr.t("Your %1 mahadasha begins", c.lord);
        if (c.kind === "antardasha") return Tr.t("Your %1–%2 antardasha begins", c.within, c.lord);
        if (c.kind === "ingress") return Tr.t("%1 moves into %2, the %3th sign from your Moon", c.planet, c.sign, c.from_moon);
        return c.kind;
    }
    function send(key, title, body, icon) {
        if (root.sent[key]) return;
        const s = Object.assign({}, root.sent);
        s[key] = true;
        root.sent = s;
        saveTimer.restart();
        Quickshell.execDetached(["notify-send", "-a", "Kundali", "-i", icon || "starred", title, body]);
    }
    function notifyFor(p, d) {
        const days = d.days || [];
        const words = Tr.t("Traditional indications from the chart, not certainties.");
        [[days[0], Tr.t("Today may be hard for %1", p.name)], [days[1], Tr.t("Tomorrow may be hard for %1", p.name)]].forEach(([day, title]) => {
            if (day && day.tone === "difficult")
                send(p.id + "|" + day.date + "|day", title, (day.reasons || []).map(root.reasonText).join("\n") + "\n" + words, "dialog-warning");
        });
        const soon = new Date(root.today() + "T12:00:00");
        soon.setDate(soon.getDate() + 3);
        (d.changes || []).forEach(c => {
            if (new Date(c.date + "T12:00:00") <= soon)
                send(p.id + "|" + c.date + "|" + c.kind + "|" + (c.lord || c.planet), Tr.t("Ahead for %1, %2", p.name, c.date),
                     root.changeText(c) + "\n" + words, "x-office-calendar");
        });
    }
}
