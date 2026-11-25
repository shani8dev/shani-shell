pragma Singleton
// Cloud sync: the session daemon (bridge/cloudsync.py) does the copying with
// rclone; this service is its only channel. It keeps the daemon alive for the
// whole session so a job outlives its window and a schedule fires on time, and
// turns the daemon's JSON-line events into one list the panel can just bind to.
// cloud.py owns the sign-ins; this never touches rclone's configuration.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property string tool: Quickshell.env("SHANI_CLOUDSYNC_TOOL") || "/usr/lib/shani-shell/cloudsync.py"
    readonly property string cloudTool: Quickshell.env("SHANI_CLOUD_TOOL") || "/usr/lib/shani-shell/cloud.py"
    readonly property var log: Log.scoped("CloudSync")

    property var jobs: []              // [{ id, remote, local, direction, conflict, bandwidth, interval, state, progress, file, history }]
    property var remotes: []           // the cloud drives cloud.py knows about
    property string note: ""           // last successful action, from a notify event
    property string error: ""          // last failure, including a missing tool
    property bool available: false
    property bool busy: true           // until the daemon's first list answer
    readonly property bool anyRunning: jobs.some(j => j.state === "running" || j.state === "paused")

    // run() is the single entry point; a long-lived daemon answers through finished().
    function run(obj) { return root.send(obj); }
    function send(obj) {
        if (!daemon.running) { root.error = Tr.t("The sync daemon is not running"); return false; }
        daemon.write(JSON.stringify(obj) + "\n");
        if (!obj.cmd || obj.cmd !== "list") root.error = "";
        return true;
    }
    function refresh() { loadRemotes(); send({ cmd: "list" }); }
    function add(id, remote, local, direction, conflict, bandwidth, interval) {
        send({ cmd: "add", id: id, remote: remote, local: local, direction: direction,
               conflict: conflict, bandwidth: bandwidth, interval: interval });
    }
    function settings(id, conflict, bandwidth, interval) {
        send({ cmd: "settings", id: id, conflict: conflict, bandwidth: bandwidth, interval: interval });
    }
    function start(id) { send({ cmd: "start", id: id }); }
    function stop(id) { send({ cmd: "stop", id: id }); }
    function pause(id) { send({ cmd: "pause", id: id }); }
    function resume(id) { send({ cmd: "resume", id: id }); }
    function remove(id) { send({ cmd: "remove", id: id }); }

    function merge(j) {
        if (!j || !j.id) return;
        const i = root.jobs.findIndex(x => x.id === j.id), l = root.jobs.slice();
        if (i < 0) l.push(j); else l[i] = Object.assign({}, l[i], j);
        root.jobs = l;
    }
    function announce(e) {
        Quickshell.execDetached(["notify-send", "-a", "Cloud sync", e.title || "Cloud sync", e.message || ""]);
    }
    function loadRemotes() { if (remoteList.running !== true) remoteList.running = true; }

    // every daemon event lands here, so the panel binds to one note/error pair
    function finished(e) {
        if (!e) return;
        if (e.event === "jobs") { root.jobs = e.jobs || []; root.busy = false; }
        else if (e.event === "job") root.merge(e.job);
        else if (e.event === "progress") root.merge({ id: e.id, progress: e.progress, file: e.file,
                                                      transferred: e.transferred, total: e.total });
        else if (e.event === "removed") root.jobs = root.jobs.filter(j => j.id !== e.id);
        else if (e.event === "error") root.error = e.error || Tr.t("That did not work");
        else if (e.event === "notify") { root.note = e.message || ""; root.announce(e); }
    }

    // one long-lived copy of the daemon, independent of any window
    Process {
        id: daemon
        running: true
        command: ["python3", root.tool]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let e = null;
                try { e = JSON.parse(line); } catch (err) { return; }
                root.finished(e);
            }
        }
        onExited: { root.busy = false; root.error = Tr.t("The sync daemon is not installed or stopped"); }
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v \"$0\"", "rclone"]
        onExited: code => { root.available = code === 0; if (code !== 0) root.error = Tr.t("rclone is not installed"); }
    }
    Process {
        id: remoteList
        command: ["python3", root.cloudTool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.remotes = Array.isArray(r) ? r : [];
                } catch (e) { root.remotes = []; }
            }
        }
    }
}
