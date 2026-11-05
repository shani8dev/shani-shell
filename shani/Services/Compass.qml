pragma Singleton
// The compass: iio-sensor-proxy's magnetometer, on the tablets and convertibles
// that have one (most laptops do not, and then no tile shows). Read only while
// the sidebar is open - monitor-sensor runs then, and at no other time.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool available: Quickshell.env("SHANI_COMPASS_CMD") !== ""
    property bool wanted: false          // the sidebar is open
    property real heading: -1            // degrees from north, clockwise; -1 = not read yet
    readonly property string point: heading < 0 ? "" : ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(heading / 45) % 8]
    readonly property string text: heading < 0 ? Tr.t("Finding north…") : point + " " + Math.round(heading) + "°"

    Process {
        running: Quickshell.env("SHANI_COMPASS_CMD") === ""
        command: ["gdbus", "call", "--system", "--dest", "net.hadess.SensorProxy", "--object-path", "/net/hadess/SensorProxy/Compass",
                  "--method", "org.freedesktop.DBus.Properties.Get", "net.hadess.SensorProxy.Compass", "HasCompass"]
        stdout: StdioCollector { onStreamFinished: root.available = text.indexOf("<true>") >= 0 }
    }
    Process {
        running: root.available && root.wanted
        command: Quickshell.env("SHANI_COMPASS_CMD") ? ["sh", "-c", Quickshell.env("SHANI_COMPASS_CMD")] : ["monitor-sensor", "--compass"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/[Cc]ompass heading(?: changed)?:\s*([\d.]+)/);
                if (m)
                    root.heading = Number(m[1]);
            }
        }
        onRunningChanged: if (!running) root.heading = -1
    }
}
