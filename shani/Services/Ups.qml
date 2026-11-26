pragma Singleton
// The UPS a desktop runs on (NUT, through bridge/ups.py): a power cut is said the
// moment the UPS takes over - how much charge and how many minutes it has - power
// coming back is said too, and a low UPS battery is critical: save your work.
// Settings > Power shows it (SettingsUps).
// Read once at start; only with a UPS present is it read again, once a minute -
// NUT gives a desktop client no change signal (its own upsmon is the one notified,
// as root), and `upsc` is one short call. No UPS: nothing runs.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_UPS_TOOL"), "ups.py")
    property var info: ({ present: false })
    readonly property bool present: !!info.present
    readonly property bool onBattery: present && !!info.onBattery
    readonly property bool low: present && !!info.low
    property bool _seen: false
    property bool _wasOnBattery: false
    property bool _wasLow: false

    // The shutdown policy is a separate read of the same bridge. The live read
    // above stays as it is: one short call a minute, only with a UPS present.
    property var policy: ({})
    property bool policyLoaded: false
    property bool policyBusy: false
    property string policyNote: ""
    property bool policyNoteOk: false

    function refresh() { reader.running = true; }
    Component.onCompleted: refresh()
    Timer { interval: 60000; repeat: true; running: root.present; onTriggered: root.refresh() }

    function loadPolicy() { if (!policyRead.running) policyRead.running = true; }
    function savePolicy(obj) {
        if (policyWrite.running) return;
        policyBusy = true;
        policyNote = "";
        policyWrite.payload = obj;
        policyWrite.stdinEnabled = true;
        policyWrite.running = true;
    }
    Process {
        id: policyRead
        command: ["python3", root.tool, "policy"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p;
                try { p = JSON.parse(text); } catch (e) { return; }
                root.policy = p || {};
                root.policyLoaded = true;
            }
        }
    }
    Process {
        id: policyWrite
        command: ["python3", root.tool, "policy-save"]
        stdinEnabled: true
        property var payload: ({})
        stdout: StdioCollector { id: policyOut }
        onStarted: { write(JSON.stringify(payload) + "\n"); stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            root.policyBusy = false;
            // policy-save reports refusal in its JSON, with exit code 0
            let r = {};
            try { r = JSON.parse(policyOut.text) || {}; } catch (e) { r = {}; }
            root.policyNoteOk = code === 0 && r.ok === true;
            root.policyNote = root.policyNoteOk
                ? Tr.t("Shutdown policy saved")
                : Tr.t("Could not save the shutdown policy. Check the values and try again.");
            if (root.policyNoteOk) root.loadPolicy();
        }
    }

    function says(i) {
        const parts = [];
        if (i.charge !== null && i.charge !== undefined) parts.push(Tr.t("%1%", Math.round(i.charge)));
        if (i.minutes) parts.push(Tr.t("about %1 min", i.minutes));
        return parts.join(" · ");
    }
    Process {
        id: reader
        command: ["python3", root.tool]
        stdout: StdioCollector {
            onStreamFinished: {
                let i;
                try { i = JSON.parse(text); } catch (e) { return; }
                root.info = i;
                if (!i.present) return;
                const ob = !!i.onBattery, lb = !!i.low;
                // said on a change only, never for the state found at start-up on mains
                if (ob && !root._wasOnBattery)
                    Quickshell.execDetached(["notify-send", "-a", Tr.t("Power"), "-i", "battery-caution",
                        Tr.t("Power cut - running on the UPS"), root.says(i)]);
                else if (!ob && root._wasOnBattery && root._seen)
                    Quickshell.execDetached(["notify-send", "-a", Tr.t("Power"), "-i", "ac-adapter",
                        Tr.t("Power is back"), Tr.t("The UPS is charging again")]);
                if (lb && !root._wasLow)
                    Quickshell.execDetached(["notify-send", "-u", "critical", "-a", Tr.t("Power"), "-i", "battery-level-0",
                        Tr.t("The UPS battery is low"), Tr.t("Save your work: the computer will shut down soon") + (root.says(i) ? " (" + root.says(i) + ")" : "")]);
                root._wasOnBattery = ob;
                root._wasLow = lb;
                root._seen = true;
            }
        }
    }
}
