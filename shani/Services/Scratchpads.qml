pragma Singleton
// Scratchpads (the drop-down terminal of Guake/Yakuake, Hyprland's special
// workspace): an app one key away, over whatever is open, and gone again on
// the same key. niri has no such thing, so it is the shell's minimise and
// restore: a pad's window floats near the top (niri's rule for app ids
// "shani-pad-*"); the key brings it to the workspace in front, or - when it is
// already there and focused - puts it away; not running, it is started.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    // [{ name, command, appId }] - appId is what the command's window gets (foot --app-id=…)
    readonly property var pads: Settings.data.scratchPads || []
    property string last: ""             // what the last toggle did (the tests)

    function find(name) { return pads.find(p => p.name === name) || null; }
    function toggle(name) {
        const pad = find(name || "terminal");
        if (!pad)
            return;
        const w = Object.values(Niri.windows).find(x => x.app_id === pad.appId);
        const here = Niri.workspaces.find(x => x.is_focused);
        if (!w) {
            last = "started";
            Quickshell.execDetached(["sh", "-c", pad.command]);
        } else if (w.id === Niri.focusedWindowId && here && w.workspace_id === here.id) {
            last = "hidden";
            Niri.minimise(w.id);
        } else {
            last = "shown";
            Niri.restore(w.id);
        }
    }
}
