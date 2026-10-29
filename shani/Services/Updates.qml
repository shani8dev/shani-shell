pragma Singleton
// ShaniOS updates, from the same contract Cassini reads:
// `shani-deploy --status --check --json` (ok, update_available,
// boot_markers.reboot_needed, current_slot). Checked at start and hourly;
// "Open Cassini" is where updating actually happens.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool known: false
    property bool available: false
    property bool rebootNeeded: false
    property string slot: ""
    readonly property bool attention: available || rebootNeeded || firmware.length > 0
    // firmware (fwupd, LVFS): the devices with a newer release — told once,
    // applied in GNOME Firmware
    property var firmware: []             // ["Thunderbolt Controller 1.2 → 1.3", …]
    property var firmwareTold: []
    // Cassini's Firmware page owns this (fwupd's devices and what LVFS offers)
    function openFirmware() { Quickshell.execDetached(["sh", "-c", "command -v shani-cassini >/dev/null && exec shani-cassini --section=firmware; exec gnome-firmware"]); }
    Process {
        id: fw
        command: ["sh", "-c", "command -v fwupdmgr >/dev/null && fwupdmgr get-updates --json --no-unreported-check 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let devs = [];
                try { devs = JSON.parse(text).Devices || []; } catch (e) { return; }
                root.firmware = devs.filter(d => (d.Releases || []).length).map(d => d.Name + " " + (d.Version || "") + " → " + d.Releases[0].Version);
                const fresh = root.firmware.filter(f => root.firmwareTold.indexOf(f) < 0);
                if (fresh.length)
                    fwTell.running = true;
                root.firmwareTold = root.firmware;
            }
        }
    }
    Process {
        id: fwTell
        command: ["notify-send", "-a", "Updates", "-i", "software-update-available", "-A", "open=Update firmware",
                  "Firmware update" + (root.firmware.length > 1 ? "s" : ""), root.firmware.join("\n")]
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "open") root.openFirmware() }
    }
    Timer { interval: 6 * 3600 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: fw.running = true }
    readonly property string summary: !known ? "" : rebootNeeded ? "Restart to finish updating"
        : available ? "An update is ready" : firmware.length ? "Firmware update ready"
        : "Up to date" + (slot ? " · slot " + slot : "")

    function check() {
        if (!proc.running)
            proc.running = true;
    }
    // Cassini's Updates page where Cassini is installed; otherwise the deploy
    // itself in a terminal (pkexec: ShaniOS's polkit asks for your own password)
    function open() {
        Quickshell.execDetached(["sh", "-c", 'command -v shani-cassini >/dev/null && exec shani-cassini --section=updates
            exec "$1" -e sh -c "pkexec /usr/local/bin/shani-deploy; echo; read -p \"Press Enter to close.\" x"', "sh", Settings.data.terminal]);
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
