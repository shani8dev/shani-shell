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
import "../Common/FormFactor.js" as FF

Singleton {
    id: root
    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri/shani-windows.kdl"
    readonly property var d: Settings.data

    // a rule is { app, title, float, mode, workspace, output, width, height }
    // float false or workspace 0 or width 0: leave that thing alone.
    // mode: tiled | floating | fullscreen | maximized | maximized_edges
    // width/height <= 1 is a proportion, > 1 a fixed pixel size.
    function kdlRule(std, r) {
        if (!std || std.trim() === "")
            return "";
        // the app-id is a regex: escape it, then escape for KDL (backslash first)
        const re = std.trim().replace(/[\\^$.*+?()[\]{}|]/g, "\\$&").replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        // a manually-entered title stays a raw regex (niri-rules-studio's rule)
        const title = (r.title || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        const match = '    match app-id="^' + re + '$"' + (title ? ' title="' + title + '"' : "");
        const mode = r.mode || (r.float ? "floating" : "tiled");
        const usesSize = mode === "tiled" || mode === "floating";
        const size = (name, v) => {
            const n = Number(v) || 0;
            if (n <= 0 || !isFinite(n)) return "";
            return n <= 1
                ? "    default-" + name + " { proportion " + n.toFixed(4) + "; }"
                : "    default-" + name + " { fixed " + Math.floor(n) + "; }";
        };
        return [
            "window-rule {",
            match,
            mode === "floating" ? "    open-floating true" : "",
            mode === "fullscreen" ? "    open-fullscreen true" : "",
            mode === "maximized" ? "    open-maximized true" : "",
            mode === "maximized_edges" ? "    open-maximized-to-edges true" : "",
            // a NAME (niri's open-on-workspace resolves named workspaces — the
            // ones configured with a `workspace "chat" {}` in the niri config)
            r.workspace ? "    open-on-workspace " + JSON.stringify(r.workspace) : "",
            r.output ? "    open-on-output " + JSON.stringify(r.output) : "",
            usesSize ? size("column-width", r.width) : "",
            usesSize ? size("window-height", r.height) : "",
            "}",
            ""
        ].filter(x => x !== "").join("\n");
    }
    // Niri applies every matching window-rule, so two blocks with the same
    // (app, title) match would combine contradictory open-* settings. Keep only
    // the newest edit for each match, at its original position.
    function uniqueRules(rules) {
        const seen = {};
        const out = [];
        for (const r of rules) {
            const key = JSON.stringify([r.app || "", r.title || ""]);
            if (seen[key] !== undefined) out[seen[key]] = r;
            else { seen[key] = out.length; out.push(r); }
        }
        return out;
    }

    // Niri's opening rules are global: apply this only to phone-only sessions,
    // never to a phone docked to a desktop monitor. Existing windows stay as-is.
    // Maximised, not fullscreen: one app at a time, with the bar kept above it as
    // a phone's status bar is (the clock, the battery, and the Island in it rather
    // than over the app's own header); a video or a game still goes fullscreen.
    readonly property string phoneRule: FF.phoneOnly(FormFactor.screens)
        ? "window-rule {\n    open-maximized true\n}\n"
        : ""

    readonly property string kdl: Settings.loaded
        ? "// written by shani-shell: Settings > Windows > Per-app rules. Edits here are replaced.\n"
            + root.phoneRule
            + root.uniqueRules(Array.from(d.windowRules || [])).map(r => root.kdlRule(r.app, r)).join("")
        : ""

    onKdlChanged: if (kdl) write.restart()
    Timer {
        id: write
        interval: 300                     // a few rules edited together: one write
        onTriggered: {
            // NiriConfig keeps the file as it was, and puts it back if niri cannot read this
            NiriConfig.write(root.path, root.kdl, Tr.t("window rules"));
        }
    }
}
