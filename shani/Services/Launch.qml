pragma Singleton
// Starting an app: every launch in the shell (launcher, dock, Ring, reopen at
// sign-in) goes through bridge/launch-app.py - GLib's desktop-file launcher,
// plus a terminal for Terminal=true apps and the other graphics card for apps
// that ask for it (PrefersNonDefaultGPU) or that the person set to it. The
// person's own launch options per app live in Settings.data.appLaunch:
//   { "org.example.Game": { gpu: "discrete", env: "MANGOHUD=1 DXVK_HUD=fps", args: "--fullscreen" } }
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_LAUNCH_TOOL") || "/usr/lib/shani-shell/launch-app.py"

    function options(id) { return (Settings.data.appLaunch || {})[id] || {}; }
    // settings.json is hand-editable: keep only values the launch bridge understands
    function setOptions(id, o) {
        const all = Object.assign({}, Settings.data.appLaunch || {});
        const clean = {};
        if (o) {
            if (["auto", "discrete", "default"].indexOf(o.gpu) >= 0) clean.gpu = o.gpu;
            if (typeof o.env === "string" && o.env.trim()) clean.env = o.env;
            if (typeof o.args === "string" && o.args.trim()) clean.args = o.args;
        }
        if (Object.keys(clean).length) all[id] = clean; else delete all[id];
        Settings.data.appLaunch = all;    // a new object: the settings file is written
    }
    // one bridge at a time: its JSON answer is read, so a second launch must not
    // overwrite the first before that answer has been seen
    property var pending: []
    property var current: null
    property var lastLaunch: ({})
    function pump() {
        if (root.current || !root.pending.length)
            return;
        root.current = root.pending.shift();
        runner.running = false;
        runner.command = root.current.argv;
        runner.running = true;
    }
    // opts: { action, gpu: "auto"|"discrete"|"default", files: [...] } - the saved options fill the gaps
    function app(id, opts) {
        if (!id)
            return;
        const o = Object.assign({}, options(id), opts || {});
        const key = id + "|" + (o.action || "") + "|" + (o.args || "") + "|" + (o.files || []).join(",");
        const now = Date.now();
        if (root.lastLaunch[key] && now - root.lastLaunch[key] < 500)
            return;                  // a double click is not a second app
        root.lastLaunch[key] = now;
        // the person's terminal, for apps that run in one (Terminal=true)
        const argv = ["env", "SHANI_TERMINAL=" + (Settings.data.terminal || "footclient"), root.tool, id, "--gpu", o.gpu || "auto"];
        if (o.action) argv.push("--action", o.action);
        for (const kv of String(o.env || "").split(/\s+/).filter(x => x.indexOf("=") > 0)) argv.push("--env", kv);
        if (o.args) argv.push("--args", o.args);
        root.pending.push({ id: id, argv: argv.concat(o.files || []) });
        root.pump();
    }
    // the bridge prints {"ok":false,"error":"..."} for a dead id, a parental
    // block or a GLib error - execDetached used to drop that silently
    Process {
        id: runner
        stdout: SplitParser {
            onRead: line => {
                let d;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (d && d.ok === false && root.current)
                    Quickshell.execDetached(["notify-send", "-a", "Shani", "-i", "dialog-warning",
                        Tr.t("Could not open %1").arg(root.current.id), String(d.error || "")]);
            }
        }
        onExited: { root.current = null; root.pump(); }
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
