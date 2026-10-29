pragma Singleton
// Per-app window rules: how each app's windows open — floating or tiled, on
// which workspace, how wide. niri supports window-rule blocks; this writes them
// into ~/.config/niri/shani-windows.kdl, which the desktop's niri config
// includes — niri reloads it the moment it changes (same pattern as the input
// file). Written whole, through a temporary file and a rename, so niri never
// reads half of it.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri/shani-windows.kdl"
    readonly property var d: Settings.data

    // a rule is { app: "foot", float: true|false, workspace: "chat", width: 0.5 }
    // float false or workspace 0 or width 0: leave that thing alone
    function kdlRule(std, r) {
        if (!std || std.trim() === "")
            return "";
        // the app-id is a regex: escape it, then escape for KDL (backslash first)
        const re = std.trim().replace(/[\\^$.*+?()[\]{}|]/g, "\\$&").replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        return [
            "window-rule {",
            "    match app-id=\"^" + re + "$\"",
            r.float ? "    open-floating true" : "",
            // a NAME (niri's open-on-workspace resolves named workspaces — the
            // ones configured with a `workspace "chat" {}` in the niri config)
            r.workspace ? "    open-on-workspace " + JSON.stringify(r.workspace) : "",
            r.width > 0 ? "    default-column-width { proportion " + (+r.width).toFixed(4) + "; }" : "",
            "}",
            ""
        ].filter(x => x !== "").join("\n");
    }
    readonly property string kdl: Settings.loaded
        ? "// written by shani-shell: Settings > Windows > Per-app rules. Edits here are replaced.\n"
            + Array.from(d.windowRules || []).map(r => root.kdlRule(r.app, r)).join("")
        : ""

    onKdlChanged: if (kdl) write.restart()
    Timer {
        id: write
        interval: 300                     // a few rules edited together: one write
        onTriggered: {
            save.command = ["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s" "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", root.path, root.kdl];
            save.running = true;
        }
    }
    Process { id: save }
}
