pragma Singleton
// Auto-rotate: iio-sensor-proxy's accelerometer -> `niri msg output <builtin>
// transform`. Only offered when the proxy reports an accelerometer.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool available: false
    readonly property bool active: Settings.data.autoRotate
    property string output: ""      // the built-in panel (eDP-*, DSI-*)

    function toggle() {
        Settings.data.autoRotate = !Settings.data.autoRotate;
    }
    function apply(orientation) {
        const t = { "normal": "normal", "left-up": "90", "bottom-up": "180", "right-up": "270" }[orientation];
        if (t && output !== "")
            Quickshell.execDetached(["niri", "msg", "output", output, "transform", t]);
    }

    Process {
        running: true
        command: ["sh", "-c", "gdbus call --system --dest net.hadess.SensorProxy --object-path /net/hadess/SensorProxy --method org.freedesktop.DBus.Properties.Get net.hadess.SensorProxy HasAccelerometer 2>/dev/null; niri msg -j outputs 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = text.indexOf("<true>") >= 0;
                const m = text.match(/"((?:eDP|DSI|LVDS)-[^"]*)"/);
                root.output = m ? m[1] : "";
            }
        }
    }
    Process {
        running: root.active && root.available
        command: ["monitor-sensor", "--accel"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/orientation changed: (\S+)/) || line.match(/Accelerometer orientation: (\S+)/);
                if (m)
                    root.apply(m[1]);
            }
        }
    }
}
