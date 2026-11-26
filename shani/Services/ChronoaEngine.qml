pragma Singleton
// Services: the person's Chronoa engine unit. No privileged helper and no
// shell string: systemctl --user starts and stops one user service. Every write is
// followed by a fresh read, so the settings page never shows a state the
// machine does not have. SHANI_CHRONOA_SYSTEMCTL lets a stand-in answer.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_CHRONOA_SYSTEMCTL") || "systemctl"
    readonly property string unit: "shani-chronoa-engine.service"

    property bool busy: false
    property string service: "unknown"       // active | inactive | unknown
    property string error: ""
    property string lastCall: ""             // short label for a live check

    property var queued: null
    property string writeError: ""

    function setEngine(on) {
        root.writeError = "";
        root.error = "";
        root.lastCall = (on ? "start " : "stop ") + root.unit;
        enqueue([on ? "start" : "stop"], true);
    }

    function refresh() {
        root.lastCall = "show " + root.unit;
        enqueue(["show", "-p", "ActiveState", "--value"], false);
    }

    function enqueue(args, thenRefresh) {
        if (proc.running) { root.queued = { args: args, thenRefresh: thenRefresh }; return; }
        launch(args, thenRefresh);
    }

    function launch(args, thenRefresh) {
        root.busy = true;
        proc.thenRefresh = thenRefresh;
        proc.command = [root.tool, "--user"].concat(args).concat([root.unit]);
        proc.running = false;
        proc.running = true;
    }

    Process {
        id: proc
        property bool thenRefresh: false
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (code !== 0)
                root.writeError = String(err.text || "").trim() || Tr.t("The Chronoa service could not be reached");
            if (proc.thenRefresh) {
                launch(["show", "-p", "ActiveState", "--value"], false);
                return;
            }
            root.busy = false;
            const state = String(out.text || "").trim();
            root.service = state === "active" || state === "inactive" ? state : "unknown";
            root.error = root.writeError;
            if (root.queued) {
                const next = root.queued;
                root.queued = null;
                launch(next.args, next.thenRefresh);
            }
        }
    }

    Component.onCompleted: refresh()
}
