pragma Singleton
// Night light: wlsunset holding one colour temperature (-t and -T one kelvin
// apart, so day and night are the same) for as long as it runs. Needs
// wlr-gamma-control, which niri offers on real outputs (not when nested).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property bool active: Settings.data.nightLight
    property bool available: false

    function toggle() {
        Settings.data.nightLight = !Settings.data.nightLight;
    }

    Process {
        running: root.active && root.available
        command: ["wlsunset", "-t", String(Settings.data.nightLightTemp), "-T", String(Settings.data.nightLightTemp + 1)]
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v wlsunset"]
        onExited: code => root.available = code === 0
    }
}
