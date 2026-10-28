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
            panel.addUser(text);
        }
        function onSystem(text) {
            panel.addSystem(text);
        }
        function onTurn(e) {
            if (e.event === "tool")
                panel.addTool(e.text);
            else if (e.event === "tool_done")
                panel.finishTool(e.ok);
            else if (e.event === "reply")
                panel.appendReply(e.text);
            else if (e.event === "approval")
                panel.addApproval(e.id, e.text, e.detail, e.options);
            else if (e.event === "approval_closed")
                panel.closeApproval(e.id);
            else if (e.event === "notice" || e.event === "error")
                panel.addSystem(e.text);
            else if (e.event === "done")
                panel.endReply();
        }
    }

    function approveLast(decision) {
        panel.approveLast(decision);
    }
}
