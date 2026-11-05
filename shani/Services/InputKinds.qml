pragma Singleton
// What this computer has to type and touch with (bridge/input-kinds.py: udev's
// database, asked once at start and again when an input device comes or goes -
// Plugged's udev events, no polling). Without a working keyboard - none at all,
// or only a touchscreen - the screen keyboard opens by itself wherever a password
// is asked, and its button stays on the desktop: nobody with only a mouse or a
// finger is ever locked out.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_INPUT_KINDS_TOOL") || "/usr/lib/shani-shell/input-kinds.py"
    property bool keyboard: true          // until asked: as before this existed
    property bool touchscreen: false
    property bool tabletSwitch: false
    // the screen keyboard comes by itself (lock, polkit) and keeps its button on the desktop
    readonly property bool typesOnScreen: !keyboard || touchscreen

    function refresh() { probe.running = true; }
    Component.onCompleted: refresh()
    Connections { target: Plugged; function onInputRevChanged() { root.refresh(); } }
    Process {
        id: probe
        command: ["python3", root.tool]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const k = JSON.parse(text);
                    root.keyboard = k.keyboard;
                    root.touchscreen = k.touchscreen;
                    root.tabletSwitch = k.tabletSwitch;
                } catch (e) {}
            }
        }
    }
}
