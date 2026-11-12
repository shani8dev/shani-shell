pragma Singleton
// To-dos (Modules/Tasks shows them): Evolution Data Server's task lists,
// through bridge/tasks.py - the same lists Thunderbird, GNOME's Endeavour and
// Chronoa read. A task due now and not done is told once, by a notification.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_TASKS_TOOL") || "/usr/lib/shani-shell/tasks.py"
    property var tasks: []            // [{ uid, summary, due, done, list, priority, notes }]
    property var lists: []            // [{ name, uid, readOnly }]
    property bool available: true
    property string error: ""
    property string selectedList: ""  // where a new task goes ("" = the first)
    property bool busy: false
    readonly property var open: tasks.filter(t => !t.done)
    readonly property var done: tasks.filter(t => t.done)
    readonly property int dueToday: open.filter(t => t.due > 0 && t.due * 1000 < endOfToday()).length
    property var told: ({})

    function endOfToday() { const d = new Date(); d.setHours(23, 59, 59, 999); return d.getTime(); }
    function refresh() { if (!reader.running) reader.running = true; if (!listReader.running) listReader.running = true; }
    function add(summary, due) {
        const s = String(summary || "").trim();
        if (s === "")
            return;
        run(["add", JSON.stringify({ summary: s, due: due || 0, list: selectedList })]);
    }
    function setDone(t, on) { run(["done", JSON.stringify({ uid: t.uid, list: t.list, done: on })]); }
    function remove(t) { run(["delete", JSON.stringify({ uid: t.uid, list: t.list })]); }
    function rename(t, summary) { if (String(summary).trim() !== "") run(["edit", JSON.stringify({ uid: t.uid, list: t.list, summary: String(summary).trim() })]); }
    function setDue(t, due) { run(["edit", JSON.stringify({ uid: t.uid, list: t.list, due: due })]); }

    // one write at a time, then the list again
    property var _queue: []
    function run(args) { _queue = _queue.concat([args]); next(); }
    function next() {
        if (writer.running || _queue.length === 0)
            return;
        busy = true;
        writer.command = ["python3", root.tool].concat(_queue[0]);
        _queue = _queue.slice(1);
        writer.running = true;
    }
    Process {
        id: writer
        stderr: StdioCollector { id: writeErr }
        onExited: code => {
            root.busy = false;
            root.error = code === 0 ? "" : (writeErr.text.trim().split("\n").pop() || Tr.t("Could not save the task"));
            root.refresh();
            root.next();
        }
    }
    Process {
        id: reader
        command: ["python3", root.tool]
        stdout: StdioCollector { onStreamFinished: { try { root.tasks = JSON.parse(text); root.available = true; } catch (e) {} } }
        onExited: code => { if (code === 2) root.available = false; }
    }
    Process {
        id: listReader
        command: ["python3", root.tool, "lists"]
        stdout: StdioCollector { onStreamFinished: { try { root.lists = JSON.parse(text); } catch (e) {} } }
    }
    // read at the start and every ten minutes; due ones told once
    Timer { interval: 10 * 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    Timer {
        interval: 60000
        running: root.open.length > 0
        repeat: true
        onTriggered: {
            const now = Date.now() / 1000;
            for (const t of root.open) {
                if (t.due > 0 && t.due <= now && t.due > now - 3600 && !root.told[t.uid]) {
                    root.told[t.uid] = true;
                    Quickshell.execDetached(["notify-send", "-a", "Tasks", "-i", "task-due", Tr.t("Due now"), t.summary]);
                }
            }
        }
    }
    function when(t) {
        if (!t.due)
            return "";
        const d = new Date(t.due * 1000), today = new Date();
        const days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(today.getFullYear(), today.getMonth(), today.getDate())) / 86400000);
        const hm = d.getHours() || d.getMinutes() ? " " + Qt.formatTime(d, Settings.data.use24h ? "HH:mm" : "h:mm AP") : "";
        return (days === 0 ? Tr.t("Today") : days === 1 ? Tr.t("Tomorrow") : days === -1 ? Tr.t("Yesterday") : days < 0 ? Tr.t("%1 days late").arg(-days) : Qt.formatDate(d, "ddd d MMM")) + hm;
    }
}
