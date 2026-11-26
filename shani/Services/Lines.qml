pragma Singleton
// Lines: the phone lines and the desk phone. The SIP accounts and the landline
// setup live in bridge/devices.py, the same tool the Devices service uses; this
// singleton is the only reader, so every window sees the same accounts.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_DEVICES_TOOL"), "devices.py")

    property var lines: []               // [{ id, name, ready, kind }]
    property var accounts: []            // the saved SIP accounts
    property var landline: ({})          // the desk phone's setup and state
    property string note: ""
    property bool busy: false

    function refresh() {
        enqueue("lines", []);
        enqueue("sip-list", []);
        enqueue("landline-state", []);
    }

    // A field object goes as one JSON argv item. Nothing is joined into a shell
    // string, so a name with quotes or spaces stays exactly what was typed.
    function addAccount(fields) { enqueue("sip-add", [JSON.stringify(fields || {})]) }
    function updateAccount(id, fields) { enqueue("sip-update", [String(id || ""), JSON.stringify(fields || {})]) }
    function removeAccount(id) { enqueue("sip-remove", [String(id || "")]) }
    function landlineSetup(host) { enqueue("landline-setup", [String(host || "")]) }
    function landlineFinish(code) { enqueue("landline-finish", [String(code || "")]) }
    function landlineForget() { enqueue("landline-forget", []) }
    function say(message) { root.note = message || ""; }

    function enqueue(what, args) {
        root.pending = root.pending.concat([{ what: what, args: args }]);
        root.pump();
    }
    function pump() {
        if (root.busy || job.running || !root.pending.length) return;
        const next = root.pending[0];
        root.pending = root.pending.slice(1);
        root.start(next.what, next.args);
    }
    function start(what, args) {
        root.busy = true;
        job.what = what;
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }
    property var pending: []

    function finished(what, text, code) {
        if (code === 127 || code === 126) {
            root.note = Tr.t("The devices service is not installed");
            return;
        }
        let data = null;
        try { data = JSON.parse(text); } catch (e) { root.note = Tr.t("Lines could not answer"); return; }
        const failed = data && data.error ? String(data.error)
            : (data && data.ok === false ? Tr.t("That did not work") : "");

        if (what === "lines") {
            root.lines = Array.isArray(data) ? data : [];
        } else if (what === "sip-list") {
            root.accounts = Array.isArray(data) ? data : [];
        } else if (what === "landline-state") {
            root.landline = data && typeof data === "object" && !Array.isArray(data) ? data : ({});
        } else if (what === "sip-add") {
            root.note = failed || Tr.t("Account added");
            if (!failed) enqueue("sip-list", []);
        } else if (what === "sip-update") {
            root.note = failed || Tr.t("Account updated");
            if (!failed) enqueue("sip-list", []);
        } else if (what === "sip-remove") {
            root.note = failed || Tr.t("Account removed");
            if (!failed) enqueue("sip-list", []);
        } else if (what === "landline-setup") {
            root.note = failed || Tr.t("Enter the code shown on the phone");
            if (!failed) enqueue("landline-state", []);
        } else if (what === "landline-finish") {
            root.note = failed || Tr.t("Desk phone connected");
            if (!failed) enqueue("landline-state", []);
        } else if (what === "landline-forget") {
            root.note = failed || Tr.t("Desk phone removed");
            if (!failed) enqueue("landline-state", []);
        }
    }

    Process {
        id: job
        property string what: ""
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.finished(job.what, out.text, code);
            root.busy = false;
            root.pump();
        }
    }

    Component.onCompleted: refresh()
}
