// Chronoa in the shell: the conversation panel. (The tool-call cue is shown
// by the Island, which is where the eye already is.)
// State lives in Services/Chronoa; this scope owns the transcript.
import Quickshell
import QtQuick
import qs.Common
import qs.Services

Scope {
    ListModel {
        id: transcript
    }

    ChronoaPanel {
        id: panel
        model: transcript
        open: Chronoa.open
        busy: Chronoa.busy
        state: Chronoa.state
        detail: Chronoa.detail

        onAsk: text => Chronoa.deliver(text)
        onAction: name => Chronoa.action(name)
        onApprove: (id, decision) => Chronoa.approve(id, decision)
        onDismiss: Chronoa.open = false
    }

    Connections {
        target: Chronoa
        function onUserAsked(text) {
            const t = String(text || "").trim();
            if (t !== "")
                panel.addUser(t);
        }
        function onSystem(text) {
            const t = String(text || "").trim();
            if (t !== "")
                panel.addSystem(t);
        }
        function onTurn(e) {
            if (!e || !e.event)
                return;
            const text = String(e.text || "");
            if (e.event === "tool") {
                if (text !== "")
                    panel.addTool(text);
            } else if (e.event === "tool_done") {
                panel.finishTool(e.ok);
            } else if (e.event === "reply") {
                if (text !== "")
                    panel.appendReply(text);
            } else if (e.event === "approval") {
                panel.addApproval(String(e.id || ""), text, String(e.detail || ""), e.options);
            } else if (e.event === "approval_closed") {
                panel.closeApproval(String(e.id || ""));
            } else if (e.event === "notice" || e.event === "error") {
                if (text !== "")
                    panel.addSystem(text);
            } else if (e.event === "done") {
                panel.endReply();
            }
        }
    }

    function approveLast(decision) {
        panel.approveLast(decision);
    }
}
