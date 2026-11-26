pragma Singleton
// AndroidTools: the Android phone's bridge. One queued Process, so a slow read
// cannot overwrite a newer answer. Every command returns one JSON object; the
// window only asks and reads, it never speaks to a tool by itself.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_ANDROID_TOOLS_TOOL"), "android_tools.py")

    property var result: ({})             // command -> its last JSON answer
    property bool busy: false
    property string note: ""
    property var pending: []

    function run(what, args) {
        root.pending = root.pending.concat([{ what: String(what || ""), args: args || [] }]);
        root.pump();
    }
    function refresh() { root.run("state", []); }
    function say(message) { root.note = message || ""; }
    function pump() {
        if (root.busy || job.running || !root.pending.length) return;
        const next = root.pending[0];
        root.pending = root.pending.slice(1);
        root.start(next);
    }
    function start(next) {
        root.busy = true;
        job.what = next.what;
        job.command = ["python3", root.tool, next.what].concat(next.args.map(a => String(a)));
        job.running = false;
        job.running = true;
    }
    function finished(what, text, code) {
        root.busy = false;
        if (code === 127 || code === 126) {
            root.note = Tr.t("The Android tools are not installed");
            return;
        }
        let data = null;
        try { data = JSON.parse(text); } catch (e) { root.note = Tr.t("Android tools could not answer"); return; }
        const value = data && typeof data === "object" ? data : ({});
        const changed = Object.assign({}, root.result);
        changed[what] = value;
        root.result = changed;
        root.note = String(value.error || "");
    }

    Process {
        id: job
        property string what: ""
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.finished(job.what, out.text, code);
            root.pump();
        }
    }

    Component.onCompleted: refresh()
}
