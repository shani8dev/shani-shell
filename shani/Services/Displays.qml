pragma Singleton
// Screens: what niri reports (`niri msg -j outputs`), and how the person wants
// each one — resolution and refresh rate, scale, rotation, position, variable
// refresh, on or off. Kept in Settings.displays by connector name and written
// as `output` blocks into the shell's niri include (InputConfig), which niri
// applies the moment it changes, and again at every login.
//
// Every change is on probation (after GNOME): "Keep these display settings?"
// for 15 seconds, then back to what was there — a mode the screen cannot show
// must not leave the person in the dark. The last screen on cannot be turned off.
// Mirroring for presenting is wl-mirror.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "DisplayModes.js" as DisplayModes

Singleton {
    id: root
    // [{ name, label, scale, x, y, width, height, transform, modes: [{w, h, r, preferred}], mode, vrrSupported, vrr, on }]
    property var outputs: []
    property bool canMirror: false
    property bool mirroring: mirror.running

    // ---- the probation -------------------------------------------------------------
    property var previous: null           // the settings to go back to, while pending
    readonly property bool pending: previous !== null
    property int countdown: 0
    function apply(name, patch) {
        apply_all([{ name: name, patch: patch }]);
    }
    function apply_all(changes) {
        const all = JSON.parse(JSON.stringify(Settings.data.displays || {}));
        for (const c of changes) {
            if (c.patch.off === true && outputs.filter(o => o.on && o.name !== c.name && !(all[o.name] || {}).off).length === 0)
                return;                   // never the last screen — and nothing to keep or revert
            all[c.name] = Object.assign(all[c.name] || {}, c.patch);
        }
        // what to go back to: recorded once the change is known to be one
        if (!pending)
            previous = JSON.parse(JSON.stringify(Settings.data.displays || {}));
        Settings.data.displays = all;
        countdown = 15;
        probation.restart();
        settle.go();
    }
    function keep() {
        previous = null;
        probation.stop();
    }
    function revert() {
        if (!pending)
            return;
        Settings.data.displays = previous;
        previous = null;
        probation.stop();
        settle.go();
    }
    Timer {
        id: probation
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0)
                root.revert();
        }
    }
    function setScale(name, scale) { apply(name, { scale: scale }); }

    // the output blocks InputConfig writes
    // on battery the built-in panel steps down to 60 Hz (Settings > Displays)
    readonly property bool slowOnBattery: Settings.data.batteryRefresh60 && PowerState.onBattery
    readonly property string kdl: {
        const all = Settings.data.displays || {};
        const names = Object.keys(all);
        if (slowOnBattery)
            for (const o of outputs)
                if (DisplayModes.internal(o.name) && names.indexOf(o.name) < 0)
                    names.push(o.name);
        return names.sort().map(name => {
            const c = all[name] || {}, l = ["output \"" + name.replace(/"/g, "") + "\" {"];
            const slow = slowOnBattery ? DisplayModes.batteryMode(outputs.find(o => o.name === name), c.mode) : "";
            if (c.off)
                l.push("    off");
            else {
                if (slow || c.mode)
                    l.push("    mode \"" + (slow || c.mode) + "\"");
                if (c.scale)
                    l.push("    scale " + c.scale);
                if (c.transform && c.transform !== "normal")
                    l.push("    transform \"" + c.transform + "\"");
                if (c.x !== undefined && c.y !== undefined)
                    l.push("    position x=" + Math.round(c.x) + " y=" + Math.round(c.y));
                if (c.vrr)
                    l.push("    variable-refresh-rate");
            }
            l.push("}");
            return l.join("\n");
        }).join("\n");
    }

    // mirror `name` in a fullscreen window: niri places it on the focused output
    function toggleMirror(name) {
        if (mirror.running) {
            mirror.running = false;
            return;
        }
        mirror.command = ["wl-mirror", "--fullscreen", name];
        mirror.running = true;
    }

    function refresh() { list.running = true; }
    Process { id: mirror }
    // mirror `source` onto `target` (a monitor just plugged in): wl-mirror's
    // fullscreen window lands on the focused output, so that one is focused first
    function mirrorOnto(target, source) {
        mirror.running = false;
        mirror.command = ["sh", "-c", 'niri msg action focus-monitor "$1"; exec wl-mirror --fullscreen "$2"', "sh", target, source];
        mirror.running = true;
    }
    // a monitor that arrives while the session runs (Plugged greets it); the
    // first listing is what was there at login, never news
    signal arrived(var output)
    property var known: null
    function rescan() { settle.go(); }
    // after a change: the setting goes to InputConfig's file and niri reloads
    // it on its own time, so outputs are read again a few times over ~4 s
    // (there is no event for "niri applied the config") - then nothing polls
    property int settleLeft: 0
    Timer {
        id: settle
        interval: 900
        onTriggered: { root.refresh(); if (--root.settleLeft > 0) restart(); }
        function go() { root.settleLeft = 4; restart(); }
    }
    // niri's transform names → the config's
    readonly property var transforms: ({ Normal: "normal", _90: "90", _180: "180", _270: "270", Flipped: "flipped",
                                         Flipped90: "flipped-90", Flipped180: "flipped-180", Flipped270: "flipped-270" })
    Process {
        id: list
        running: true
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    const conf = Settings.data.displays || {};
                    root.outputs = Object.keys(o).sort().map(k => {
                        const v = o[k], lg = v.logical;
                        const m = (v.modes || []).map(x => ({ w: x.width, h: x.height, r: x.refresh_rate / 1000, preferred: x.is_preferred }));
                        const cur = v.current_mode !== null && v.current_mode !== undefined ? m[v.current_mode] : null;
                        return {
                            name: k,
                            label: [v.make, v.model].filter(x => x && x !== "Unknown").join(" ") || k,
                            on: !!lg,
                            scale: lg ? lg.scale : 1,
                            x: lg ? lg.x : 0, y: lg ? lg.y : 0,
                            width: lg ? lg.width : (cur ? cur.w : 1920), height: lg ? lg.height : (cur ? cur.h : 1080),
                            transform: lg ? (root.transforms[lg.transform] || "normal") : ((conf[k] || {}).transform || "normal"),
                            modes: m,
                            mode: cur ? cur.w + "x" + cur.h + "@" + cur.r.toFixed(3) : "",
                            vrrSupported: !!v.vrr_supported,
                            vrr: !!v.vrr_enabled
                        };
                    });
                    const names = root.outputs.map(x => x.name);
                    if (root.known === null)
                        root.known = names;
                    else
                        for (const out of root.outputs.filter(x => root.known.indexOf(x.name) < 0)) {
                            root.known = root.known.concat([out.name]);
                            root.arrived(out);
                        }
                } catch (e) {}
            }
        }
    }
    // niri reports outputs coming and going on its event stream; a plug-in shows up here
    // a monitor plugged in or out is a wl_output appearing or going, which
    // Quickshell.screens follows - no need to ask niri every 5 s
    Connections { target: Quickshell; function onScreensChanged() { settle.go(); } }
    Process {
        running: true
        command: ["sh", "-c", "command -v wl-mirror"]
        onExited: code => root.canMirror = code === 0
    }
}
