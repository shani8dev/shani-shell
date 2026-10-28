pragma Singleton
// What a hot corner does, by name — shared by the corners and `ipc hotCorner`.
import Quickshell
import QtQuick
import qs.Common
import qs.Services

Singleton {
    property string last: ""            // for `state`
    function run(action) {
        last = action;
        if (action === "overview")
            Niri.action("toggle-overview");
        else if (action === "launcher")
            Ui.toggleLauncher();
        else if (action === "sidebar")
            Ui.toggleControlCenter();
        else if (action === "chronoa")
            Chronoa.open = !Chronoa.open;
        else if (action === "lock")
            Lock.lock();
    }
}
