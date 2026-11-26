pragma Singleton
// The boot slots: which one this machine is running from, which is current, and
// what a boot left behind. bridge/bootinfo.py reads `shani-deploy --status
// --json` (no root, no deploy lock); the window only shows it. Rollback stays
// with shani-deploy and authorisation, as the page says.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_BOOTINFO_TOOL"), "bootinfo.py")

    property bool available: false
    property var rows: []
    property string note: ""

    // Secure boot, read with the slots (no root). Codes and counts come from
    // the bridge; the words for them live in the page.
    property var secureboot: ({})

    // The installed-file check runs only when the person asks for it: it goes
    // through authorisation. Nothing here is guessed when a read fails.
    property var verifyChecks: []
    property var verifyAdvice: []
    property var verifyUnread: []
    property string verifyNote: ""
    property bool verifyBusy: false
    property bool verifyAvailable: false

    function refresh() {
        run.running = false; run.running = true;
        sbRun.running = false; sbRun.running = true;
    }

    function verify() {
        if (verifyRun.running || root.verifyBusy)
            return;
        root.verifyChecks = [];
        root.verifyAdvice = [];
        root.verifyUnread = [];
        root.verifyNote = "";
        root.verifyAvailable = false;
        root.verifyBusy = true;
        verifyRun.running = true;
    }

    Process {
        id: run
        command: ["python3", root.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                root.available = !!d.available;
                root.rows = Array.isArray(d.rows) ? d.rows : [];
                root.note = d.note || "";
            }
        }
    }

    Process {
        id: sbRun
        command: ["python3", root.tool, "secureboot"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                root.secureboot = (d && typeof d === "object" && !Array.isArray(d)) ? d : {};
            }
        }
    }

    Process {
        id: verifyRun
        command: ["python3", root.tool, "verify"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) { d = {}; }
                if (!d || typeof d !== "object" || Array.isArray(d))
                    d = {};
                root.verifyAvailable = !!d.available;
                root.verifyChecks = Array.isArray(d.checks) ? d.checks : [];
                root.verifyAdvice = Array.isArray(d.advice) ? d.advice : [];
                root.verifyUnread = Array.isArray(d.unread) ? d.unread : [];
                root.verifyNote = typeof d.error === "string" ? d.error : "";
            }
        }
        onExited: code => {
            // No JSON and a bad exit: a failed read, never an empty good one.
            if (code !== 0 && root.verifyNote === "")
                root.verifyNote = "failed";
            root.verifyBusy = false;
        }
    }

    Component.onCompleted: refresh()
}
