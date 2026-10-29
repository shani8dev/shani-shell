pragma Singleton
// Location through GeoClue2 (shani-peripherals ships it): the computer asks
// where it is, and Weather + NightLight pick up the latitude/longitude instead
// of a typed city. Off by default (privacy): the person opts in, and the
// daemon is the one that actually authorises the request.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var d: Settings.data
    property bool available: false        // GeoClue2 + helper present
    property bool running: false
    property real lat: 0
    property real lon: 0
    property real accuracy: 0
    property string error: ""
    property string city: ""             // reverse-geocoded lazily by Weather

    function refresh() {
        if (!root.d.useLocation || root.running)
            return;
        root.running = true;
        root.error = "";
        geo.running = true;
    }
    Process {
        id: geo
        command: [Quickshell.env("SHANI_LOCATION_TOOL") || "/usr/lib/shani-shell/location.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.running = false;
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() || "bad output" }; }
                if (r.error) {
                    root.error = r.error;
                    return;
                }
                root.lat = r.lat;
                root.lon = r.lon;
                root.accuracy = r.accuracy || 0;
                // feed the rest of the shell: weather + night light + dark style
                if (root.lat !== 0 || root.lon !== 0) {
                    Settings.data.weatherLat = root.lat;
                    Settings.data.weatherLon = root.lon;
                }
            }
        }
        onExited: code => {
            if (code !== 0 && root.running) {
                root.running = false;
                root.error = "helper exited " + code;
            }
        }
    }

    // re-run when the toggle flips on, and periodically (once an hour) while on
    onDChanged: if (root.d.useLocation) root.refresh()
    Timer {
        interval: 3600000
        repeat: true
        running: Settings.loaded && root.d.useLocation
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // available: GeoClue's client is installed (what the helper asks through)
    Process {
        running: true
        command: ["test", "-x", "/usr/lib/geoclue-2.0/demos/where-am-i"]
        onExited: code => root.available = code === 0
    }
}