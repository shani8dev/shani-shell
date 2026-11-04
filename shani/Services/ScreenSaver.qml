pragma Singleton
// The screen saver (Android's, macOS's): after a while with nothing touched, a
// full-screen clock over the wallpaper on every screen, gone at the first key
// or move - before the dim and the lock, never instead of them (it shows only
// when its minutes come first). Idle is ext-idle-notify, the same as Idle's
// stages: the monitor is rebuilt when its minutes change (IdleMonitor keeps
// the timeout it was made with), and a Caffeine or an inhibiting app holds it.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property bool enabled: Settings.data.screenSaverEnabled
    readonly property int minutes: Settings.data.screenSaverMinutes
    property bool preview: false          // Settings' "Preview": until a key or a click
    readonly property bool active: preview || (mon.item !== null && mon.item.isIdle && !Lock.locked)

    Loader {
        id: mon
        function rearm() { active = false; active = root.enabled && root.minutes > 0 && !Idle.caffeine; }
        Component.onCompleted: rearm()
        Connections {
            target: root
            function onEnabledChanged() { mon.rearm(); }
            function onMinutesChanged() { mon.rearm(); }
        }
        Connections { target: Idle; function onCaffeineChanged() { mon.rearm(); } }
        sourceComponent: IdleMonitor {
            timeout: root.minutes * 60
            respectInhibitors: true
        }
    }
}
