pragma Singleton
// Chronoa state for the whole shell (bar pill, cue, panel). Turn events are
// re-emitted for Modules/Chronoa, which owns the transcript.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root

    property bool open: false
    property bool busy: false
    property bool visible: true
    property string state: "offline"
    property string detail: ""
    property string cueText: ""
    property bool cueHold: false
    property string title: ""
    property string art: ""           // Chronoa's latest mascot frame (a PNG it rewrites)
    property int artRev: 0
    property string step: ""          // the tool step in progress
    property var approval: null       // { id, text, detail, options } awaiting an answer

    signal turn(var e)                // a dev.shani.chronoa.Agent event
    signal system(string text)        // a line for the transcript
    signal userAsked(string text)

    readonly property color color: state === "listening" || state === "idle" ? Theme.accent
        : state === "speaking" ? Theme.blue : state === "waiting" ? Theme.red
        : state === "offline" ? Theme.faint : Theme.amber
    readonly property string label: ["offline", "thinking", "listening", "speaking", "waiting"].indexOf(state) >= 0 ? state : "ready"

    function ask(text) {
        userAsked(text);
        deliver(text);
    }
    function deliver(text) {
        // progress and approvals show in the Island; the conversation panel
        // opens when asked for (or on an error), not on every question
        busy = true;
        if (!Bridge.send({ op: "ask", text: text })) {
            busy = false;
            system("Chronoa bridge is not connected — is shani-chronoa-bridge.service running?");
            open = true;
        }
    }
    function action(name) {
        Bridge.send({ op: "action", name: name });
    }
    function approve(id, decision) {
        Bridge.send({ op: "approve", id: id, decision: decision });
        if (approval && approval.id === id)
            approval = null;
    }

    function handleTurn(e) {
        if (e.event === "thinking") {
            state = "thinking";
            busy = true;
        } else if (e.event === "state") {
            state = e.state || "thinking";
            busy = state !== "idle";
        } else if (e.event === "tool") {
            state = "thinking";
            busy = true;
            step = e.text || "";
        } else if (e.event === "tool_done") {
            step = "";
        } else if (e.event === "reply") {
            state = "speaking";
        } else if (e.event === "approval") {
            state = "waiting";
            approval = { id: e.id, text: e.text || "", detail: e.detail || "",
                         options: (e.options && e.options.length) ? e.options.map(String) : ["Allow this once", "Deny"] };
        } else if (e.event === "approval_closed") {
            if (approval && approval.id === e.id)
                approval = null;
            state = busy ? "thinking" : "idle";
        } else if (e.event === "done") {
            busy = false;
            state = "idle";
            step = "";
        }
        turn(e);
    }

    Timer {
        id: cueTimer
        interval: root.cueHold ? 8000 : 3200
        onTriggered: root.cueText = ""
    }

    Connections {
        target: Bridge
        function onConnectedChanged() {
            if (!Bridge.connected)
                root.state = "offline";
        }
        function onMessage(e) {
            if (e.type === "state" || e.type === "hello") {
                root.state = e.state || "idle";
                root.detail = e.detail || "";
                root.title = e.title || "";
                if (e.type === "hello") {
                    root.visible = e.visible !== false;
                    if (e.art)
                        root.art = e.art;
                }
            } else if (e.type === "art") {
                root.art = e.path;
                root.artRev = e.rev || root.artRev + 1;
            } else if (e.type === "cue") {
                root.cueText = e.text;
                root.cueHold = !!e.hold;
                cueTimer.restart();
            } else if (e.type === "mascot") {
                root.visible = !!e.visible;
            } else if (e.type === "notice") {
                if (root.open)
                    root.system(e.text);
            } else if (e.type === "error") {
                root.busy = false;
                root.state = "idle";
                root.system(e.text);
                root.open = true;
            } else if (e.type === "event") {
                root.handleTurn(e);
            }
        }
    }
}
