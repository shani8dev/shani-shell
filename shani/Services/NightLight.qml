pragma Singleton
// Night light: wlsunset. By hand (or a focus mode that warms, Sleep) it holds
// one colour temperature — -t and -T one kelvin apart, so day and night are the
// same. On a schedule it runs all the time and fades by itself: from sunset to
// sunrise where the person is (the weather location), or between two set
// times. Needs wlr-gamma-control, which niri offers on real outputs (not nested).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property bool active: Settings.data.nightLight
    readonly property string schedule: Settings.data.nightLightSchedule
    readonly property bool located: Settings.data.weatherLat !== 0 || Settings.data.weatherLon !== 0
    // what wlsunset is asked for: by hand / focus, else the schedule, else nothing
    readonly property string mode: root.active || Focus.nightLight ? "hold"
        : schedule === "sunset" && located ? "sunset" : schedule === "custom" || schedule === "sunset" ? "custom" : ""
    // the schedule's times as "now warm?" for the tile (a sunset schedule: roughly)
    property bool scheduledNow: false
    property bool available: false

    function toggle() {
        Settings.data.nightLight = !Settings.data.nightLight;
    }

    readonly property var command: {
        const t = String(Settings.data.nightLightTemp);
        if (mode === "hold")
            return ["wlsunset", "-t", t, "-T", String(Settings.data.nightLightTemp + 1)];
        if (mode === "sunset")
            return ["wlsunset", "-t", t, "-l", String(Settings.data.weatherLat), "-L", String(Settings.data.weatherLon)];
        // custom: -S is when the day starts (warmth ends), -s when the evening does
        return ["wlsunset", "-t", t, "-S", Settings.data.nightLightTo, "-s", Settings.data.nightLightFrom];
    }
    Process {
        id: sunset
        running: root.mode !== "" && root.available
        command: root.command
        // a new schedule: restart with it
        onCommandChanged: if (running) { running = false; Qt.callLater(() => running = Qt.binding(() => root.mode !== "" && root.available)); }
    }
    function minutes(hhmm) {
        const m = /^(\d\d?):(\d\d)$/.exec(hhmm || "");
        return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : -1;
    }
    Timer {
        interval: 60000
        running: root.schedule !== "manual"
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const d = new Date(), now = d.getHours() * 60 + d.getMinutes();
            const from = root.schedule === "sunset" ? 19 * 60 : root.minutes(Settings.data.nightLightFrom);
            const to = root.schedule === "sunset" ? 6 * 60 + 30 : root.minutes(Settings.data.nightLightTo);
            root.scheduledNow = from >= 0 && to >= 0 && (from < to ? now >= from && now < to : now >= from || now < to);
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v wlsunset"]
        onExited: code => root.available = code === 0
    }
}
