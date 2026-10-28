pragma Singleton
// Idle stages over ext-idle-notify: dim -> lock -> screens off -> suspend, with
// separate battery timings. Monitors respect idle inhibitors (video players,
// the Caffeine tile). Each stage is its own monitor with a fixed timeout bound
// to settings — never re-armed while idle, which resets isIdle without a wake
// event (a bug other shells hit).
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property bool battery: Power.onBattery
    readonly property int dimAfter: Settings.data.dimAfter
    readonly property int lockAfter: battery ? Settings.data.lockAfterBattery : Settings.data.lockAfter
    readonly property int offAfter: battery ? Settings.data.screenOffAfterBattery : Settings.data.screenOffAfter
    readonly property int suspendAfter: battery ? Settings.data.suspendAfterBattery : Settings.data.suspendAfter
    readonly property bool dimmed: dimMon.isIdle && !Lock.locked
    readonly property bool caffeine: Settings.data.caffeine || Focus.caffeine
    readonly property bool lockIdle: lockMon.isIdle

    function setCaffeine(on) {
        Settings.data.caffeine = on;
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

        sourceComponent: IdleMonitor {
            timeout: stage.seconds
            respectInhibitors: true
            onIsIdleChanged: if (isIdle) stage.idle()
        }
    }

    Stage {
        id: dimMon
        seconds: root.dimAfter
        on: !root.caffeine
    }
    Stage {
        id: lockMon
        seconds: root.lockAfter
        on: !root.caffeine
        onIdle: Lock.lock()
    }
    Stage {
        seconds: root.offAfter
        on: !root.caffeine
        // niri powers outputs back on by itself at the next input
        onIdle: Niri.action("power-off-monitors")
    }
    Stage {
        seconds: root.suspendAfter
        on: !root.caffeine
        onIdle: Power.suspend()
    }
}
