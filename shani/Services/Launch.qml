pragma Singleton
// Starting an app: every launch in the shell (launcher, dock, Ring, reopen at
// sign-in) goes through bridge/launch-app.py - GLib's desktop-file launcher,
// plus a terminal for Terminal=true apps and the other graphics card for apps
// that ask for it (PrefersNonDefaultGPU) or that the person set to it. The
// person's own launch options per app live in Settings.data.appLaunch:
//   { "org.example.Game": { gpu: "discrete", env: "MANGOHUD=1 DXVK_HUD=fps", args: "--fullscreen" } }
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_LAUNCH_TOOL") || "/usr/lib/shani-shell/launch-app.py"

    function options(id) { return (Settings.data.appLaunch || {})[id] || {}; }
    function setOptions(id, o) {
        const all = Object.assign({}, Settings.data.appLaunch || {});
        if (!o || (!o.gpu && !o.env && !o.args)) delete all[id]; else all[id] = o;
        Settings.data.appLaunch = all;    // a new object: the settings file is written
    }
    // opts: { action, gpu: "auto"|"discrete"|"default", files: [...] } - the saved options fill the gaps
    function app(id, opts) {
        if (!id)
            return;
        const o = Object.assign({}, options(id), opts || {});
        // the person's terminal, for apps that run in one (Terminal=true)
        const argv = ["env", "SHANI_TERMINAL=" + (Settings.data.terminal || "foot"), root.tool, id, "--gpu", o.gpu || "auto"];
        if (o.action) argv.push("--action", o.action);
        for (const kv of String(o.env || "").split(/\s+/).filter(x => x.indexOf("=") > 0)) argv.push("--env", kv);
        if (o.args) argv.push("--args", o.args);
        Quickshell.execDetached(argv.concat(o.files || []));
    }

    // the terminal chosen in Settings is everyone's: written as the person's
    // freedesktop default (~/.config/niri-xdg-terminals.list, read by
    // xdg-terminal-exec - so GLib, xdg-open and other apps open the same one)
    readonly property string terminal: Settings.loaded ? (Settings.data.terminal || "") : ""
    onTerminalChanged: {
        if (!terminal)
            return;
        const e = DesktopEntries.byId(terminal) || DesktopEntries.heuristicLookup(terminal);
        if (!e)
            return;
        Quickshell.execDetached(["sh", "-c", 'd="${XDG_CONFIG_HOME:-$HOME/.config}"; mkdir -p "$d" && printf "%s.desktop\\n" "$1" > "$d/niri-xdg-terminals.list"', "sh", e.id]);
    }
}
