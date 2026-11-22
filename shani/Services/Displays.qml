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

    // ---- temporary (this-session-only) output changes ---------------------------
    // Like the Noctalia niri-displays plugin: `niri msg output <port> ...` changes
    // the live session only and is never written to config.kdl. A niri restart
    // restores the configured values. Our `apply()` above remains the persistent
    // path with its 15 s probation; these are for "try it now".
    function temporary(port, args) {
        if (!port) return;
        Quickshell.execDetached(["niri", "msg", "output", port].concat(args.map(String)));
        Qt.callLater(root.rescan);
    }
    function tempMode(port, w, h, refreshHz) {
        // niri takes WxH@Hz, e.g. 3840x2160@59.997
        const hz = refreshHz ? Number(refreshHz).toFixed(3) : null;
        const spec = hz ? (w + "x" + h + "@" + hz) : (w + "x" + h);
        temporary(port, ["mode", spec]);
    }
    function tempScale(port, scale) { temporary(port, ["scale", String(scale)]); }
    function tempTransform(port, transform) { temporary(port, ["transform", transform]); }
    function tempPosition(port, x, y) { temporary(port, ["position", "set", "--", String(x), String(y)]); }
    function tempEnabled(port, on) {
        if (!on && outputs.filter(o => o.on && o.name !== port).length === 0)
            return;   // never leave the session with no screen
        temporary(port, [on ? "on" : "off"]);
    }

    // ---- scale presets (resolution=scale, optionally PORT:WxH=SCALE) -------------
    // Applied automatically when a resolution changes, after the pattern of the
    // niri-displays plugin. The most specific matching preset (port-specific,
    // last one) wins.
    readonly property var scalePresets: Settings.data.displayScalePresets || []
    function presetScale(port, w, h) {
        const res = w + "x" + h;
        let chosen = null;
        for (const entry of scalePresets) {
            const s = String(entry || "");
            const m = s.match(/^(?:([\w-]+):)?(\d+x\d+)=([\d.]+)$/);
            if (!m || m[2] !== res) continue;
            if (m[1] && m[1] !== port) continue;
            chosen = parseFloat(m[3]);   // last valid match wins
        }
        return chosen;
    }
    function applyPresets() {
        for (const o of outputs) {
            if (!o.on) continue;
            const scale = presetScale(o.name, o.width, o.height);
            if (scale !== null && Math.abs((o.scale || 1) - scale) > 0.001)
                tempScale(o.name, scale);
        }
    }
    onOutputsChanged: if (Settings.data.displayScalePresetsAuto !== false) applyPresets()

    // the output blocks InputConfig writes
    // on battery the built-in panel steps down to 60 Hz (Settings > Displays)
    readonly property bool slowOnBattery: Settings.data.batteryRefresh60 && PowerState.onBattery
    readonly property string kdl: {
        const all = Settings.data.displays || {};
        const names = Object.keys(all);
        if (Settings.data.startupOutput && names.indexOf(Settings.data.startupOutput) < 0)
            names.push(Settings.data.startupOutput);
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
                // a resolution of your own (WxH@Hz) the screen does not list: niri makes the mode
                if (c.customMode && !slow)
                    l.push("    mode custom=true \"" + String(c.customMode).replace(/[^0-9x@.]/g, "") + "\"");
                else if (slow || c.mode)
                    l.push("    mode \"" + (slow || c.mode) + "\"");
                if (c.scale)
                    l.push("    scale " + c.scale);
                if (c.transform && c.transform !== "normal")
                    l.push("    transform \"" + c.transform + "\"");
                if (c.x !== undefined && c.y !== undefined)
                    l.push("    position x=" + Math.round(c.x) + " y=" + Math.round(c.y));
                if (c.vrr)
                    l.push("    variable-refresh-rate");
                // colour depth: 10 bits a channel where the cable and screen take it (8: the safe one)
                if (c.bpc)
                    l.push("    max-bpc " + parseInt(c.bpc));
                // a VR headset: lent whole to the VR runtime (SteamVR, Monado), not a desktop screen
                if (c.vrLease)
                    l.push("    drm-lease");
                // the screen the session starts on
                if (Settings.data.startupOutput === name)
                    l.push("    focus-at-startup");
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
    signal departed(string name)            // a monitor unplugged (Plugged ends Presenting with it)
    // the built-in panel turned off for a monitor, and that monitor unplugged: the
    // panel comes back on (never a laptop with every screen dark); its own mode,
    // scale and place are kept, only "off" goes
    property int panelsRestored: 0
    onDeparted: name => {
        const all = JSON.parse(JSON.stringify(Settings.data.displays || {}));
        const lit = outputs.filter(o => o.name !== name && o.on && !(all[o.name] || {}).off);
        if (lit.length > 0) return;
        for (const o of outputs.filter(o => DisplayModes.internal(o.name) && (all[o.name] || {}).off)) {
            delete all[o.name].off;
            Settings.data.displays = all;
            panelsRestored++;
            Quickshell.execDetached(["niri", "msg", "output", o.name, "on"]);
        }
    }
    property var known: null
    function rescan() { settle.go(); }
    function stopMirror() { mirror.running = false; }
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
                            physical: v.physical_size || [0, 0],     // mm; [0, 0] when it does not say
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
                    if (root.known !== null)
                        for (const gone of root.known.filter(n => names.indexOf(n) < 0)) {
                            root.known = root.known.filter(n => n !== gone);
                            root.departed(gone);
                        }
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
