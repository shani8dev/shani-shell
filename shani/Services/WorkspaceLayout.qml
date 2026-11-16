pragma Singleton
// Floating workspaces (after Omarchy 4.5): a workspace's windows either scroll
// in niri's columns (as always) or float, free to overlap, each workspace its
// own. Mod+Shift+Space switches the focused one; the bar marks a floating one.
// niri has no per-workspace mode, so the shell keeps it: a window that opens
// on a floating workspace is floated, and switching moves the windows already
// there. Kept by output and place ("eDP-1:2"), as niri gives workspaces no
// lasting id.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    function keyOf(ws) { return ws ? (ws.name || ((ws.output || "") + ":" + ws.idx)) : ""; }
    function isFloating(ws) { return (Settings.data.floatingWorkspaces || []).indexOf(keyOf(ws)) >= 0; }
    readonly property var focusedWs: Niri.workspaces.find(w => w.is_focused) || null
    readonly property bool focusedFloating: focusedWs !== null && (Settings.data.floatingWorkspaces || []).indexOf(keyOf(focusedWs)) >= 0
    function toggle() {
        const ws = focusedWs;
        if (!ws) return;
        const k = keyOf(ws);
        const list = Array.from(Settings.data.floatingWorkspaces || []);
        const on = list.indexOf(k) < 0;
        Settings.data.floatingWorkspaces = on ? list.concat([k]) : list.filter(x => x !== k);
        for (const w of Object.values(Niri.windows))
            if (w.workspace_id === ws.id && !!w.is_floating !== on)
                Niri.action(on ? "move-window-to-floating" : "move-window-to-tiling", "--id", String(w.id));
    }
    Connections {
        target: Niri
        function onWindowOpened(w) {
            const ws = Niri.workspaces.find(x => x.id === w.workspace_id);
            if (ws && root.isFloating(ws) && !w.is_floating)
                Niri.action("move-window-to-floating", "--id", String(w.id));
        }
    }
}
