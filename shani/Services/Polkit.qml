pragma Singleton
// The session's polkit authentication agent: without one, every privileged
// action (Cassini updates, pkexec, mounting) fails silently in a niri session.
// Modules/Polkit draws the dialog for `flow`.
//
// When polkit offers several identities (root and the wheel members) it
// defaults to the first; we preselect the user who is sitting here. Switching
// identity cancels the running PAM conversation, which polkit reports as a
// failure — that one is swallowed. (Pattern from DankMaterialShell / Dux Shell,
// MIT, Services/PolkitService.qml.)
import Quickshell
import Quickshell.Services.Polkit
import QtQuick

Singleton {
    id: root

    readonly property alias agent: agent
    readonly property bool active: agent.isActive
    readonly property var flow: agent.flow
    property bool switching: false
    property string error: ""

    function currentUserIdentity(flow) {
        const ids = flow ? flow.identities : null;
        if (!ids || ids.length < 2)
            return null;
        const user = Quickshell.env("USER");
        for (let i = 0; i < ids.length; i++) {
            if (!ids[i].isGroup && ids[i].string === user)
                return ids[i];
        }
        return null;
    }

    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: {
            root.error = "";
            const id = root.currentUserIdentity(flow);
            if (id && id !== flow.selectedIdentity) {
                root.switching = true;
                flow.selectedIdentity = id;
                root.switching = false;
            }
        }
    }

    Connections {
        target: agent.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            if (!root.switching)
                root.error = "Wrong password — try again";
        }
    }
}
