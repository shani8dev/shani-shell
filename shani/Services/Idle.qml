pragma Singleton
// Idle stages over ext-idle-notify: dim -> lock -> screens off -> suspend, with
// separate battery timings. Monitors respect idle inhibitors (video players,
// the Caffeine tile). Each stage is its own monitor with a fixed timeout bound
// to settings — never re-armed while idle, which resets isIdle without a wake
// event (a bug other shells hit).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property bool battery: Power.onBattery
    readonly property int dimAfter: battery ? Settings.data.dimAfterBattery : Settings.data.dimAfter
    readonly property int lockAfter: battery ? Settings.data.lockAfterBattery : Settings.data.lockAfter
    readonly property int offAfter: battery ? Settings.data.screenOffAfterBattery : Settings.data.screenOffAfter
    readonly property int suspendAfter: battery ? Settings.data.suspendAfterBattery : Settings.data.suspendAfter
    readonly property bool dimmed: dimMon.isIdle && !Lock.locked
    readonly property bool caffeine: Settings.data.caffeine || Focus.caffeine
    // apps keeping the screen awake over org.freedesktop.ScreenSaver (a video
    // playing in Firefox, mpv): bridge/screensaver.py holds them, releases one
    // when its app leaves the bus, and sends the list on every change
    property var appInhibitors: []        // [{ app, reason }]
    readonly property bool keptAwake: appInhibitors.length > 0
    // "Firefox", "Firefox and mpv": the apps' own names where their desktop entry says
    readonly property string keptAwakeBy: {
        const names = [...new Set(appInhibitors.map(i => {
            const e = DesktopEntries.heuristicLookup(String(i.app || ""));
            return e ? e.name : String(i.app || "");
        }).filter(n => n))];
        return names.length < 2 ? (names[0] || "") : names.slice(0, -1).join(", ") + " " + Tr.t("and") + " " + names[names.length - 1];
    }
    // dim, lock, screen off and sleep wait while either holds
    readonly property bool awake: caffeine || keptAwake
    signal activity()
    Connections {
        target: Bridge
        function onMessage(m) {
            if (m.type !== "screensaver")
                return;
            if (m.inhibitors)
                root.appInhibitors = m.inhibitors;
            else if (m.op === "activity")
                root.activity();          // SimulateUserActivity: idle starts over
            else if (m.op === "lock")
                Lock.lock();
        }
        // the bridge restarted: what it held went with it (it sends the list again on connecting)
        function onConnectedChanged() { if (!Bridge.connected) root.appInhibitors = []; }
    }
    // niri forwards the kernel's lid switch to TabletMode through the shell's
    // switchEvent IPC: opening the lid is presence, so re-arm the stages rather
    // than leaving the screen dimmed/locked with no other input.
    Connections {
        target: TabletMode
        function onLidClosedChanged() { if (!TabletMode.lidClosed) root.activity(); }
    }
    readonly property bool lockIdle: lockMon.isIdle

    function setCaffeine(on) {
        Settings.data.caffeine = on;
        Settings.data.caffeineBoot = on ? bootId.text().trim() : "";
    }
    // left on when the machine went down: off after the restart, as the
    // tile is everywhere else (a shell restart within the same boot keeps it)
    FileView {
        id: bootId
        path: "/proc/sys/kernel/random/boot_id"
        onLoaded: root.forgetOldCaffeine()
    }
    Connections { target: Settings; function onLoadedChanged() { root.forgetOldCaffeine(); } }
    function forgetOldCaffeine() {
        const boot = bootId.text().trim();
        if (Settings.loaded && boot !== "" && Settings.data.caffeine && Settings.data.caffeineBoot !== boot)
            setCaffeine(false);
    }

    // One stage of idle. IdleMonitor ignores a change to `timeout` once made
    // (measured: created at 300 s, set to 2 s, never idle) — and settings load
    // after startup, so every stage starts at its default. So the monitor is
    // rebuilt whenever its timeout or switch changes: a re-arm on a *settings*
    // change, never the re-arm-while-idle that loses the wake event.
    component Stage: Loader {
        id: stage
        required property int seconds
        required property bool on
        readonly property bool isIdle: item !== null && item.isIdle
        signal idle()

        function rearm() {
            active = false;
            active = on && seconds > 0;
        }
        onSecondsChanged: rearm()
        onOnChanged: rearm()
        Component.onCompleted: rearm()
        // an app said the person is there (SimulateUserActivity): a fresh count -
        // never while locked, which only the person ends
        Connections { target: root; function onActivity() { if (!Lock.locked) stage.rearm(); } }

        sourceComponent: IdleMonitor {
            timeout: stage.seconds
            respectInhibitors: true
            onIsIdleChanged: if (isIdle) stage.idle()
        }
    }

    Stage {
        id: dimMon
        seconds: root.dimAfter
        on: !root.awake
    }
    Stage {
        id: lockMon
        seconds: root.lockAfter
        on: !root.awake
        onIdle: Lock.lock()
    }
    Stage {
        seconds: root.offAfter
        on: !root.awake
        // niri powers outputs back on by itself at the next input
        onIdle: Niri.action("power-off-monitors")
    }
    Stage {
        seconds: root.suspendAfter
        on: !root.awake
        onIdle: Power.suspend()
    }
    // a 30 s heads-up before the idle sleep: notify-send -A waits for the click
    // and prints the action's key, which re-arms every stage (Cancel).
    Stage {
        id: suspendWarnMon
        seconds: root.suspendAfter - 30
        on: !root.awake && root.suspendAfter > 30
        onIdle: root.warnSuspend()
    }
    Process {
        id: suspendWarn
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "cancel") root.activity() }
    }
    function warnSuspend() {
        if (suspendWarn.running) return;
        suspendWarn.command = ["notify-send", "-a", Tr.t("Power"), "-i", "dialog-warning",
            "-A", "cancel=" + Tr.t("Cancel suspend"),
            Tr.t("Suspending in 30 seconds"), Tr.t("The computer has been idle. It will sleep soon.")];
        suspendWarn.running = true;
    }
}
