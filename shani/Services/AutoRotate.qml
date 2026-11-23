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
    property string applied: ""     // last transform we set, so off can restore it
    property int retries: 0         // bounded restarts when monitor-sensor dies

    function toggle() {
        Settings.data.autoRotate = !Settings.data.autoRotate;
    }
    function apply(orientation) {
        const t = { "normal": "normal", "left-up": "90", "bottom-up": "180", "right-up": "270" }[orientation];
        if (t && output !== "") {
            Quickshell.execDetached(["niri", "msg", "output", output, "transform", t]);
            root.applied = t;
        }
    }
    // switching auto-rotate off must leave the panel upright, not stuck at the last tilt
    onActiveChanged: if (!active && root.applied !== "" && root.applied !== "normal") root.apply("normal")

    Process {
        id: sensor
        // a locked screen must not keep spinning because the tablet moved in a bag
        running: root.active && root.available && !Lock.locked
        command: ["monitor-sensor", "--accel"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/orientation changed: (\S+)/) || line.match(/Accelerometer orientation: (\S+)/);
                if (m)
                    root.apply(m[1]);
            }
        }
        onStarted: root.retries = 0
        // iio-sensor-proxy can restart under us; don't leave auto-rotate dead forever
        onExited: if (root.active && root.available && !Lock.locked && root.retries++ < 3) retry.restart()
    }
    // a fresh bind (not just running = true): the old running binding is still true
    Timer {
        id: retry
        interval: 2000
        onTriggered: {
            sensor.running = false;
            sensor.running = Qt.binding(() => root.active && root.available && !Lock.locked);
        }
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
}
