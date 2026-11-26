pragma Singleton
// PhoneTools: the phone's own music, files, remote and link, plus the switches
// that keep working with every window closed. One bridge, one queued Process,
// so a slow read cannot overwrite a newer answer.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/JobQueue.js" as JobQueue
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_PHONE_TOOLS_TOOL"), "phone_tools.py")

    property var music: ({})             // { state, title, artist, player, summary }
    property var files: []               // [{ path, name, size, when }]
    property bool receiveFiles: false
    property var remote: ({})            // { on, status, note }
    property var link: ({})              // { paired, name, address, status, note }
    property var audio: ({})             // { where, note } for call sound
    property var switches: []            // [{ key, label, detail, on }]
    property string note: ""
    property bool busy: false

    function refresh() {
        enqueue("music", ["status"]);
        enqueue("files", ["received"]);
        enqueue("files", ["receive", "state"]);
        enqueue("remote", ["status"]);
        enqueue("link", ["state"]);
        enqueue("audio", ["state"]);
        enqueue("background", ["list"]);
    }
    function musicAction(action) { enqueue("music", [String(action || "status")]) }
    function filesSend(path) { enqueue("files", ["send", String(path || "")]) }
    function filesReceive(on) { enqueue("files", ["receive", on ? "on" : "off"]) }
    function remoteAction(action, key) {
        const args = [String(action || "status")];
        if (key !== undefined && key !== null && String(key) !== "") args.push(String(key));
        enqueue("remote", args);
    }
    function linkAction(action, value) {
        const args = [String(action || "state")];
        if (value !== undefined && value !== null && String(value) !== "") args.push(String(value));
        enqueue("link", args);
    }
    function audioWhere(where) { enqueue("audio", [String(where || "state")]) }
    function backgroundSet(key, on) { enqueue("background", ["set", String(key || ""), on ? "on" : "off"]) }
    function say(message) { root.note = message || ""; }

    function enqueue(what, args) {
        root.pending = root.pending.concat([{ what: what, args: args }]);
        root.pump();
    }
    function pump() { JobQueue.pump(root, job); }
    function start(what, args) {
        root.busy = true;
        job.what = what;
        job.arg = args.length ? String(args[0]) : "";
        job.command = ["python3", root.tool, what].concat(args);
        job.running = false;
        job.running = true;
    }
    property var pending: []

    function finished(what, text, code) {
        root.busy = false;
        if (code === 127 || code === 126) {
            root.note = Tr.t("The phone tools are not installed");
            return;
        }
        let data = null;
        try { data = JSON.parse(text); } catch (e) { root.note = Tr.t("Phone tools could not answer"); return; }
        const failed = data && data.error ? String(data.error)
            : (data && data.ok === false ? Tr.t("That did not work") : "");

        if (what === "music") {
            root.music = data && typeof data === "object" ? data : ({});
            if (failed) root.note = failed;
        } else if (what === "files") {
            if (job.arg === "received") {
                root.files = Array.isArray(data && data.files) ? data.files : [];
            } else if (job.arg === "receive") {
                if (!failed) root.receiveFiles = !!data.on;
                else root.note = failed;
            } else {
                root.note = failed || Tr.t("Sent to the phone");
            }
        } else if (what === "remote") {
            if (job.arg === "status") {
                root.remote = data && typeof data === "object" ? data : ({});
            } else {
                root.note = failed || (data && data.note) || Tr.t("Done on the phone");
                root.remote = Object.assign({}, root.remote, { note: root.note },
                    !failed && data && typeof data.on === "boolean" ? { on: data.on } : {});
            }
        } else if (what === "link") {
            if (job.arg === "state") {
                root.link = data && typeof data === "object" ? data : ({});
            } else {
                root.note = failed || (data && data.note) || Tr.t("Done");
                enqueue("link", ["state"]);
            }
        } else if (what === "audio") {
            if (job.arg === "state") {
                root.audio = data && typeof data === "object" ? data : ({});
            } else {
                root.note = failed || (data && data.note) || Tr.t("Call sound changed");
                enqueue("audio", ["state"]);
            }
        } else if (what === "background") {
            if (job.arg === "set") {
                root.note = failed || Tr.t("Saved");
                enqueue("background", ["list"]);
            } else {
                root.switches = Array.isArray(data && data.switches) ? data.switches : [];
            }
        }
    }

    Process {
        id: job
        property string what: ""
        property string arg: ""
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.finished(job.what, out.text, code);
            root.pump();
        }
    }

    Component.onCompleted: refresh()
}
