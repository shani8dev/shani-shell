pragma Singleton
// ShaniOS updates, from the same contract Cassini reads:
// `shani-deploy --status --check --json` (ok, update_available,
// boot_markers.reboot_needed, current_slot). Checked at start and hourly;
// "Open Cassini" is where updating actually happens.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool known: false
    property bool available: false
    property bool rebootNeeded: false
    property string slot: ""
    readonly property bool attention: available || rebootNeeded
    readonly property string summary: !known ? "" : rebootNeeded ? "Restart to finish updating"
        : available ? "An update is ready" : "Up to date" + (slot ? " · slot " + slot : "")

    function check() {
        if (!proc.running)
            proc.running = true;
    }
    function open() {
        Quickshell.execDetached(["shani-cassini"]);
    }

    Process {
        id: proc
        command: ["sh", "-c", "command -v shani-deploy >/dev/null && exec shani-deploy --status --check --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    root.known = !!s.ok;
                    root.available = !!s.update_available;
                    root.rebootNeeded = !!(s.boot_markers && s.boot_markers.reboot_needed);
                    root.slot = s.current_slot || "";
                } catch (e) {
                    root.known = false;
                }
            }
        }
    }
    Timer {
        interval: 3600 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }
}
