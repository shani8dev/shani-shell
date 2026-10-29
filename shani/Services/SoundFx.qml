pragma Singleton
// Sound effects (after JamesDSP / ViPER4Android): an equaliser with presets,
// bass boost, headphone correction from AutoEq, an impulse response
// (convolver — JamesDSP's and ViPER's IR collections are plain .wav files),
// stereo width and headphone crossfeed. All of it is PipeWire's own
// filter-chain with its built-in filters: no extra package, no DSP of ours.
//
// The shell writes one filter-chain config from the settings and runs it as
// its own `pipewire -c` process: a virtual output, "ShaniOS sound effects",
// that becomes the default and plays into the real one. Picking another
// output in the sidebar makes that the target instead, and effects stay on.
// Every change rebuilds the graph (PipeWire builds it once, at start).
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var d: Settings.data
    readonly property bool on: d.fxEnabled
    readonly property string sinkName: "effect_input.shani"
    readonly property string path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-effects.conf"
    readonly property var bands: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    readonly property var presets: ({
        "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass": [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
        "Treble": [0, 0, 0, 0, 0, 0, 2, 4, 5, 6],
        "Vocal": [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1],
        "Rock": [4, 3, 1, -1, -1, 0, 2, 3, 4, 4],
        "Pop": [-1, 0, 2, 3, 3, 1, 0, -1, -1, -1],
        "Classical": [3, 2, 1, 0, 0, 0, -1, 0, 2, 3],
        "Loudness": [5, 4, 2, 0, -1, -1, 0, 2, 4, 5],
        "Laptop speakers": [-6, -4, -1, 1, 2, 1, 1, 2, 3, 2]
    })
    // the real output effects play into: what was default before, and what is picked later
    property string target: ""
    readonly property bool running: fx.running
    readonly property var defaultSink: Pipewire.defaultAudioSink

    function applyPreset(name) {
        d.fxEq = presets[name] || presets.Flat;
        d.fxPreset = name;
    }

    // AutoEq's "ParametricEQ.txt": "Preamp: -6.2 dB" and
    // "Filter 1: ON PK Fc 105 Hz Gain -2.4 dB Q 0.70" (PK, LSC, HSC)
    function parseAutoEq(text) {
        const out = [];
        for (const line of (text || "").split("\n")) {
            const m = /Filter\s*\d*:\s*ON\s+(PK|LSC|HSC|LS|HS)\s+Fc\s+([\d.]+)\s*Hz\s+Gain\s+(-?[\d.]+)\s*dB(?:\s+Q\s+([\d.]+))?/i.exec(line);
            if (m)
                out.push({ type: m[1].toUpperCase().startsWith("L") ? "bq_lowshelf" : m[1].toUpperCase().startsWith("H") ? "bq_highshelf" : "bq_peaking",
                           f: parseFloat(m[2]), g: parseFloat(m[3]), q: parseFloat(m[4] || "0.707") });
        }
        return out;
    }

    // ---- the graph -------------------------------------------------------------
    function num(x) { return (Math.round(x * 10000) / 10000).toString(); }
    readonly property string conf: {
        const eq = Array.from(d.fxEq || []);
        const auto = parseAutoEq(d.fxAutoEq);
        const filters = [];
        bands.forEach((f, i) => { if (eq[i]) filters.push({ type: i === 0 ? "bq_lowshelf" : i === bands.length - 1 ? "bq_highshelf" : "bq_peaking", f: f, g: eq[i], q: 1.4 }); });
        if (d.fxBass)
            filters.push({ type: "bq_lowshelf", f: 90, g: d.fxBass, q: 0.7 });
        auto.forEach(a => filters.push(a));
        // headroom: as much as the largest boost, so boosting never clips
        const boost = Math.max(0, ...filters.map(x => x.g));
        const pre = Math.pow(10, -boost / 20);
        const w = d.fxWidth, cf = d.fxCrossfeed ? 0.3 : 0;
        const nodes = [], links = [];
        for (const c of ["L", "R"]) {
            let prev = "";
            filters.forEach((x, i) => {
                const n = "f" + c + i;
                nodes.push(`{ type = builtin name = ${n} label = ${x.type} control = { "Freq" = ${num(x.f)} "Q" = ${num(x.q)} "Gain" = ${num(x.g)} } }`);
                if (prev) links.push(`{ output = "${prev}:Out" input = "${n}:In" }`);
                prev = n;
            });
            if (d.fxIr) {
                const n = "ir" + c;
                nodes.push(`{ type = builtin name = ${n} label = convolver config = { filename = "${d.fxIr.replace(/"/g, "")}" channel = ${c === "L" ? 0 : 1} } }`);
                if (prev) links.push(`{ output = "${prev}:Out" input = "${n}:In" }`);
                prev = n;
            }
            // a plain copy when nothing else is on, so the graph always has an input
            if (!prev) {
                nodes.push(`{ type = builtin name = in${c} label = copy }`);
                prev = "in" + c;
            }
            nodes.push(`{ type = builtin name = last${c} label = copy }`);
            links.push(`{ output = "${prev}:Out" input = "last${c}:In" }`);
            if (cf) {
                nodes.push(`{ type = builtin name = lp${c} label = bq_lowpass control = { "Freq" = 700 "Q" = 0.5 } }`);
                nodes.push(`{ type = builtin name = dl${c} label = delay config = { "max-delay" = 0.01 } control = { "Delay (s)" = 0.0003 } }`);
                links.push(`{ output = "last${c}:Out" input = "lp${c}:In" }`);
                links.push(`{ output = "lp${c}:Out" input = "dl${c}:In" }`);
            }
        }
        // each side: itself (a), the other side (b: width), the other side low-passed and late (crossfeed)
        const a = (1 + w) / 2 * pre, b = (1 - w) / 2 * pre;
        for (const [c, o] of [["L", "R"], ["R", "L"]]) {
            nodes.push(`{ type = builtin name = mix${c} label = mixer control = { "Gain 1" = ${num(a)} "Gain 2" = ${num(b)} "Gain 3" = ${num(cf * pre)} } }`);
            links.push(`{ output = "last${c}:Out" input = "mix${c}:In 1" }`);
            links.push(`{ output = "last${o}:Out" input = "mix${c}:In 2" }`);
            if (cf)
                links.push(`{ output = "dl${o}:Out" input = "mix${c}:In 3" }`);
        }
        // loudness levelling last: an EBU R128 meter, its short-term loudness
        // turned into a gain that holds it near the target (PipeWire's ebur128 plugin)
        let outs = ["mixL:Out", "mixR:Out"];
        if (d.fxLoudness) {
            nodes.push(`{ type = ebur128 name = meter label = ebur128 }`);
            nodes.push(`{ type = ebur128 name = level label = lufs2gain control = { "Target LUFS" = -16 } }`);
            nodes.push(`{ type = builtin name = lvL label = mixer }`);
            nodes.push(`{ type = builtin name = lvR label = mixer }`);
            links.push(`{ output = "mixL:Out" input = "meter:In FL" }`);
            links.push(`{ output = "mixR:Out" input = "meter:In FR" }`);
            links.push(`{ output = "meter:Out FL" input = "lvL:In 1" }`);
            links.push(`{ output = "meter:Out FR" input = "lvR:In 1" }`);
            links.push(`{ output = "meter:Shortterm LUFS" input = "level:LUFS" }`);
            links.push(`{ output = "level:Gain" input = "lvL:Gain 1" }`);
            links.push(`{ output = "level:Gain" input = "lvR:Gain 1" }`);
            outs = ["lvL:Out", "lvR:Out"];
        }
        const first = c => filters.length ? "f" + c + "0" : d.fxIr ? "ir" + c : "in" + c;
        return `# written by shani-shell (Settings > Sound effects); rewritten on every change
context.properties = { log.level = 0 }
context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert support.* = support/libspa-support }
context.modules = [
  { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }
  { name = libpipewire-module-protocol-native }
  { name = libpipewire-module-client-node }
  { name = libpipewire-module-adapter }
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "ShaniOS sound effects"
      media.name = "ShaniOS sound effects"
      filter.graph = {
        nodes = [
          ${nodes.join("\n          ")}
        ]
        links = [
          ${links.join("\n          ")}
        ]
        inputs = [ "${first("L")}:In" "${first("R")}:In" ]
        outputs = [ "${outs[0]}" "${outs[1]}" ]
      }
      audio.channels = 2
      audio.position = [ FL FR ]
      capture.props = { node.name = "${sinkName}" media.class = Audio/Sink }
      playback.props = { node.name = "effect_output.shani" node.passive = true${root.target ? ` target.object = "${root.target}"` : ""} }
    }
  }
]
`;
    }

    // write, then (re)start; settle changes for a moment so a slider drag is one rebuild
    onConfChanged: if (on) rebuild.restart()
    onOnChanged: {
        if (on) {
            if (defaultSink && defaultSink.name !== sinkName)
                target = defaultSink.name;
            rebuild.restart();
        } else {
            fx.running = false;
            // back to the real output
            const real = Pipewire.nodes.values.find(n => n.name === root.target);
            if (real)
                Pipewire.preferredDefaultAudioSink = real;
        }
    }
    Timer {
        id: rebuild
        interval: 400
        onTriggered: {
            fx.running = false;
            save.command = ["sh", "-c", 'printf "%s" "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", root.path, root.conf];
            save.running = true;
        }
    }
    Process { id: save; onExited: code => { if (code === 0 && root.on) fx.running = true; } }
    Process {
        id: fx
        command: ["pipewire", "-c", root.path]
        stderr: StdioCollector { id: fxErr }
        onExited: code => { if (root.on && code !== 0) root.error = fxErr.text.trim().split("\n").pop() || "the effects stopped"; }
    }
    property string error: ""
    onRunningChanged: if (running) error = ""

    // ---- the microphone: RNNoise between the real mic and a cleaned-up source ----
    readonly property bool micOn: d.micNoise
    readonly property string micPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-mic.conf"
    readonly property string micName: "effect_output.shani_mic"
    property string micTarget: ""
    readonly property var defaultSource: Pipewire.defaultAudioSource
    readonly property string micConf: `# written by shani-shell (Settings > Sound > Noise suppression)
context.properties = { log.level = 0 }
context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert support.* = support/libspa-support }
context.modules = [
  { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }
  { name = libpipewire-module-protocol-native }
  { name = libpipewire-module-client-node }
  { name = libpipewire-module-adapter }
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "ShaniOS noise-cancelled microphone"
      media.name = "ShaniOS noise-cancelled microphone"
      filter.graph = { nodes = [ { type = ladspa name = rnnoise plugin = "librnnoise_ladspa" label = noise_suppressor_stereo control = { "VAD Threshold (%)" = 50.0 } } ] }
      audio.channels = 2
      audio.position = [ FL FR ]
      capture.props = { node.name = "effect_input.shani_mic" node.passive = true${micTarget ? ` target.object = "${micTarget}"` : ""} }
      playback.props = { node.name = "${micName}" media.class = Audio/Source }
    }
  }
]
`
    onMicOnChanged: {
        if (micOn) {
            if (defaultSource && defaultSource.name !== micName)
                micTarget = defaultSource.name;
            micRebuild.restart();
        } else {
            mic.running = false;
            // by name: the previous default may be a monitor, which Quickshell will not take as a source
            if (root.micTarget)
                Quickshell.execDetached(["pactl", "set-default-source", root.micTarget]);
        }
    }
    onMicConfChanged: if (micOn) micRebuild.restart()
    Timer {
        id: micRebuild
        interval: 300
        onTriggered: {
            mic.running = false;
            micSave.command = ["sh", "-c", 'printf "%s" "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", root.micPath, root.micConf];
            micSave.running = true;
        }
    }
    Process { id: micSave; onExited: code => { if (code === 0 && root.micOn) mic.running = true; } }
    Process {
        id: mic
        command: ["pipewire", "-c", root.micPath]
        stderr: StdioCollector { id: micErr }
        onExited: code => { if (root.micOn && code !== 0) root.micError = micErr.text.trim().split("\n").pop() || "noise suppression stopped"; }
    }
    property string micError: ""
    readonly property bool micRunning: mic.running
    readonly property var micNode: Pipewire.nodes.values.find(n => n.name === micName) || null
    onMicNodeChanged: if (micOn && micNode) Pipewire.preferredDefaultAudioSource = micNode
    onDefaultSourceChanged: {
        if (!micOn || !defaultSource || defaultSource.name === micName || defaultSource.name === "effect_input.shani_mic")
            return;
        micTarget = defaultSource.name;
    }

    // our output appears: make it the default. Another output picked while on:
    // that becomes the target, and ours the default again.
    readonly property var fxNode: Pipewire.nodes.values.find(n => n.name === sinkName) || null
    onFxNodeChanged: if (on && fxNode) Pipewire.preferredDefaultAudioSink = fxNode
    onDefaultSinkChanged: {
        if (!on || !defaultSink || defaultSink.name === sinkName || defaultSink.name === "effect_output.shani")
            return;
        target = defaultSink.name;              // rebuilds through conf
    }
}
