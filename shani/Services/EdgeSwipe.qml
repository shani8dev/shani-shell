pragma Singleton
// What an edge swipe does (Modules/EdgeSwipe; Common/Gestures.js names it):
// one place, so a finger, the IPC and the tests do the same.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    property string last: ""              // the last swipe's action (the tests)
    // touch-first screens: the strips are up (Modules/EdgeStrips)
    readonly property bool touchFirst: ["tablet", "phone"].indexOf(FormFactor.focused.profile) >= 0
    readonly property int strips: Settings.data.edgeSwipes && touchFirst && !Lock.locked ? 4 : 0
    function run(action) {
        if (!action || Lock.locked) return;
        last = action;
        if (action === "launcher") {
            const open = Ui.launcher;
            Ui.closeAll();
            if (!open) Ui.toggleLauncher("");
        } else if (action === "quick-settings") {
            const open = Ui.controlCenter;
            Ui.closeAll();
            if (!open) Ui.toggleControlCenter();
        } else if (action === "back") {
            // one Back for the remote, the edge swipe and the IPC
            Ui.back();
        } else if (action === "overview")
            Niri.action("toggle-overview");
    }
}
