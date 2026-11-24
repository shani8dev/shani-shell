pragma Singleton
// Hardware sensors from bridge/sensors.py (lm-sensors' hwmon sysfs, no deps).
// The System Monitor is the only reader, so the helper runs on a slow 3 s timer
// only while that window is open: nothing is forked at idle. The bridge returns
// [] when the machine has no sensors, which is an honest empty state, not an
// error.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_SENSORS_TOOL") || "/usr/lib/shani-shell/sensors.py"
    readonly property int interval: 3000

    // set by the monitor's visibility; another surface showing the sensor
    // section can take a token here without a second reader
    property bool wanted: Ui.processes
    property var sensors: []
    property bool loading: false
    property bool answered: false        // at least one read came back, even []
    property string error: ""

    onWantedChanged: {
        if (!wanted) {
            run.running = false;
            root.loading = false;
            root.answered = false;
            root.sensors = [];
            root.error = "";
        }
    }

    function refresh() {
        if (root.loading || !root.wanted) return;
        root.loading = true;
        run.running = true;
    }

    Timer {
        interval: root.interval
        running: root.wanted
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Process {
        id: run
        command: ["python3", root.tool]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.loading) return;
                let arr = null;
                try { arr = JSON.parse(text); } catch (e) { arr = null; }
                root.loading = false;
                if (Array.isArray(arr)) {
                    root.answered = true;
                    root.sensors = arr;
                    root.error = "";
                } else {
                    root.error = Tr.t("Cannot be read");
                }
            }
        }
        onExited: code => {
            if (code !== 0 && root.loading) {
                root.loading = false;
                root.error = Tr.t("Cannot be read");
            }
        }
    }
}
