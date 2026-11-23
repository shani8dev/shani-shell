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
    property string version: ""          // the release on this slot (/etc/shani-version)
    property string remoteStable: ""     // what the stable channel offers
    property string remoteLatest: ""     // what the latest channel offers
    readonly property string candidate: root.channel === "latest" ? root.remoteLatest : root.remoteStable
    readonly property bool attention: available || rebootNeeded || firmware.length > 0
    // shani-deploy channels: "stable" (default) | "latest" — see shani-deploy/scripts/shani-deploy.sh
    readonly property string channel: Settings.data.updateChannel || "stable"
    function setChannel(ch) {
        if (ch !== "stable" && ch !== "latest") ch = "stable";
        Settings.data.updateChannel = ch;
        check();
    }
    // firmware (fwupd, LVFS): the devices with a newer release — told once per
    // release, persisted across restarts; opens Cassini's Firmware page
    property var firmware: []             // ["Thunderbolt Controller 1.2 → 1.3", …]
    property var firmwareTold: []
    FileView {
        id: firmwareToldFile
        path: Quickshell.statePath("firmware-told.json")
        printErrors: false
        atomicWrites: true
        onLoaded: { try { root.firmwareTold = JSON.parse(text()); } catch (e) { root.firmwareTold = []; } }
        onLoadFailed: root.firmwareTold = []
    }
    // ---- installing ---------------------------------------------------------
    // The shell does the update itself: shani-deploy through pkexec, so the
    // shell's own polkit agent asks and the answer appears in the Island. The
    // deploy writes the *other* slot and leaves this one running, so nothing
    // here can break the session you are using.
    property bool installing: false
    property var progress: []             // the last lines of shani-deploy, newest last
    property string installError: ""
    property string note: ""              // the last outcome, shown once

    function install() {
        if (root.installing) return;
        if (!root.available) {
            root.note = Tr.t("There is no update to install.");
            return;
        }
        root.installing = true;
        root.progress = [];
        root.installError = "";
        installer.command = ["sh", "-c",
            'command -v shani-deploy >/dev/null || exit 3; exec pkexec /usr/local/bin/shani-deploy',
            "sh"];
        installer.running = false;
        installer.running = true;
    }

    Process {
        id: installer
        stdout: SplitParser {
            onRead: line => {
                const l = String(line).trim();
                if (l === "") return;
                root.progress = root.progress.concat([l]).slice(-40);
            }
        }
        stderr: StdioCollector { id: installErr }
        onExited: code => {
            root.installing = false;
            if (code === 0) {
                root.note = Tr.t("The other slot is updated. Restart when you are ready.");
                root.check();
            } else if (code === 3) {
                root.installError = Tr.t("shani-deploy is not installed.");
            } else if (code === 126 || code === 127) {
                root.installError = Tr.t("That needed administrator rights and was not given.");
            } else {
                root.installError = (installErr.text.trim().split("\n").pop()
                    || (root.progress.length ? root.progress[root.progress.length - 1] : ""))
                    || Tr.t("The update did not finish.");
            }
        }
    }

    // ---- firmware ----------------------------------------------------------
    // fwupd's own GUI is not installed; the shell reads the updates and points
    // at `fwupdmgr` for the ones that need a reboot.
    function openFirmware() {
        Quickshell.execDetached(["sh", "-c", "command -v fwupdmgr >/dev/null && exec fwupdmgr get-updates"]);
    }
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
                firmwareToldFile.setText(JSON.stringify(root.firmwareTold));
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
    function reviewWithChronoa() {
        if (!root.available && root.firmware.length === 0) return;
        const msg = root.firmware.length > 0
            ? ("Review firmware updates: " + root.firmware.join(", "))
            : "Review pending system updates for safety and impact before installing.";
        Chronoa.ask(msg);
    }

    // kept for callers that asked for the old "open the updater" behaviour
    function open() { root.install(); }

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
                    root.version = s.version || "";
                    const remote = s.remote || {};
                    root.remoteStable = remote.stable || "";
                    root.remoteLatest = remote.latest || "";
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
