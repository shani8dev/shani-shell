pragma Singleton
// Services: the person's own units and scheduled jobs, with real writes. The
// bridge uses `systemctl --user` and the person's crontab: no root, no pkexec.
// One Process for reads, one for writes; a write is followed by a fresh read so
// the window never shows a state the machine does not have.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_SERVICES_TOOL"), "services.py")

    property string tab: "services"       // services | timers | cron
    property var services: []
    property var timers: []
    property var cron: []
    property string note: ""
    property bool busy: false

    function refresh() { run("services", []); run("timers", []); run("cron", []) }
    function setTab(t) { root.tab = t; root.note = "" }
    function unit(name, action) { write("unit", [action, name]) }
    function cronAdd(schedule, command) { write("cron-add", [schedule, command]) }
    function cronRemove(index) { write("cron-remove", [String(index)]) }

    function run(what, args) {
        if (reader.running) { root.queue = root.queue.concat([{ what: what, args: args }]); return; }
        reader.what = what;
        reader.command = ["python3", root.tool, what].concat(args);
        reader.running = false;
        reader.running = true;
    }
    property var queue: []

    function write(what, args) {
        root.busy = true;
        writer.what = what;
        writer.command = ["python3", root.tool, what].concat(args);
        writer.running = false;
        writer.running = true;
    }

    function answer(text, what) {
        let d = {};
        try { d = JSON.parse(text) || {}; } catch (e) { return d; }
        if (what === "services") root.services = Array.isArray(d) ? d : [];
        else if (what === "timers") root.timers = Array.isArray(d) ? d : [];
        else if (what === "cron") root.cron = Array.isArray(d) ? d : [];
        return d;
    }

    Process {
        id: reader
        property string what: ""
        stdout: StdioCollector { id: readOut }
        onExited: code => {
            root.answer(readOut.text, reader.what);
            if (root.queue.length) {
                const next = root.queue[0];
                root.queue = root.queue.slice(1);
                root.run(next.what, next.args);
            }
        }
    }

    Process {
        id: writer
        property string what: ""
        stdout: StdioCollector { id: writeOut }
        onExited: code => {
            root.busy = false;
            const d = root.answer(writeOut.text, "");
            root.note = d.error ? String(d.error)
                : (writer.what === "cron-remove" ? Tr.t("Job removed") : Tr.t("Saved"));
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
