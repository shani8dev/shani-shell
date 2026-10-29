pragma Singleton
// PipeWire through Quickshell's built-in client: default sink/source, volume,
// mute, output switching, and the privacy signal "something is recording".
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool ready: Pipewire.ready && sink !== null && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : true
    readonly property bool micMuted: source && source.audio ? source.audio.muted : true
    readonly property real micVolume: micNode && micNode.audio ? micNode.audio.volume : 0

    // Classified by the node's type flags: a node's `properties` (media.class,
    // application.name …) stay empty until it is tracked — measured: every
    // filter on media.class matched nothing. Playback stream = Audio|Stream|Sink.
    function has(n, f) { return (n.type & f) === f; }
    // the sound-effects output (SoundFx) is not a device: picking a device while it is on retargets it
    readonly property var sinks: Pipewire.nodes.values.filter(n => has(n, PwNodeType.AudioSink) && !has(n, PwNodeType.Stream) && n.name !== "effect_input.shani")
    readonly property var sources: Pipewire.nodes.values.filter(n => has(n, PwNodeType.AudioSource) && !has(n, PwNodeType.Stream))
    // apps capturing from a microphone, and apps playing sound (the mixer)
    readonly property var recorders: Pipewire.nodes.values.filter(n => has(n, PwNodeType.AudioInStream))
    readonly property var players: Pipewire.nodes.values.filter(n => has(n, PwNodeType.AudioOutStream))
    readonly property bool micInUse: recorders.length > 0
    // a screen being shared: a video source with no device behind it (the
    // portal's screencast stream); cameras carry device.api. Video sources are
    // tracked below, so their properties are there to read.
    readonly property var videoSources: Pipewire.nodes.values.filter(n => has(n, PwNodeType.VideoSource))
    readonly property bool screenShared: videoSources.some(n => n.ready && !n.properties["device.api"])

    readonly property string icon: {
        if (!ready || muted || volume <= 0.001)
            return "audio-volume-muted";
        if (volume < 0.34)
            return "audio-volume-low";
        if (volume < 0.67)
            return "audio-volume-medium";
        return "audio-volume-high";
    }

    // up to 150 % with over-amplification (Settings > Sound), 100 % otherwise
    readonly property real maxVolume: Settings.data.overAmplify ? 1.5 : 1.0
    function setVolume(v) {
        if (!ready)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(maxVolume, v));
    }
    function step(delta) {
        setVolume(volume + delta);
    }
    // a volume key: the step chosen in Settings
    function stepKey(up) { step((up ? 1 : -1) * Settings.data.volumeStep / 100); }
    function toggleMute() {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }
    // the microphone the slider and mute act on: the real one, also while noise
    // suppression (SoundFx) stands in front of it as the default source — the
    // level belongs on the microphone itself, before the noise is taken out
    readonly property var micNode: source && source.name === "effect_output.shani_mic"
        ? (Pipewire.nodes.values.find(n => n.name === SoundFx.micTarget) || source) : source
    function toggleMic() {
        if (micNode && micNode.audio)
            micNode.audio.muted = !micNode.audio.muted;
    }
    function setMicVolume(v) {
        if (micNode && micNode.audio)
            micNode.audio.volume = Math.max(0, Math.min(1.0, v));
    }
    function useSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }
    function useSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // ---- where an app plays: a moved stream keeps its own target, not the
    // default's — the graph is the truth (an Active link from the stream)
    // (Quickshell's nodes carry no links: the graph's are Pipewire.linkGroups,
    // one per pair of linked nodes)
    function streamSink(n) {
        if (!n)
            return null;
        const g = Pipewire.linkGroups.values.find(x => x.source === n && x.target && x.target !== n);
        return g ? g.target : null;
    }
    // hand an app to another device: PipeWire's own way - the stream's
    // target.object in the default metadata, which WirePlumber follows (and
    // keeps for that app); by node id, so nothing has to map it to PulseAudio's
    // sink-input numbers (Quickshell's Pipewire is read-only here)
    function moveStream(n, sinkNode) {
        if (!n || !sinkNode)
            return;
        Quickshell.execDetached(["pw-metadata", "-n", "default", String(n.id), "target.object", String(sinkNode.name)]);
    }

    // ---- left/right balance on whatever the default device is. The channel
    // volumes carry it, and the loudness never jumps: the louder side stays at
    // the volume it had, the quieter one loses a share. Centred again, both go
    // back to that volume (once - a device that was never off-centre is left
    // alone); re-applied when the default device changes.
    readonly property int balance: Settings.data.audioBalance
    property int balanceApplied: 0
    Timer {
        id: balanceApply
        interval: 120
        onTriggered: {
            const b = root.balance || 0;
            if (!root.sink || !root.ready || b < -100 || b > 100 || (b === 0 && root.balanceApplied === 0))
                return;
            // the louder channel is the volume (an average would sink a little each time)
            const vols = Array.from(root.sink.audio.volumes || []);
            const v = Math.round((vols.length ? Math.max(...vols) : root.volume) * 100);
            const other = Math.round(v * (100 - Math.abs(b)) / 100) + "%";
            pactl.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@",
                             b > 0 ? other : v + "%",
                             b > 0 ? v + "%" : other];
            pactl.running = true;
            root.balanceApplied = b;
        }
    }
    Process { id: pactl }
    function setBalance(b) {
        const t = Math.max(-100, Math.min(100, Math.round(b)));
        if (t !== Settings.data.audioBalance)
            Settings.data.audioBalance = t;
    }
    onBalanceChanged: balanceApply.restart()
    onSinkChanged: balanceApply.restart()
    function nodeName(n) {
        return n ? (n.description || n.nickname || n.name) : "";
    }
    function streamName(n) {
        const p = n.properties;
        return p["application.name"] || p["media.name"] || n.name;
    }

    // Binding a node's audio properties requires tracking it.
    PwObjectTracker {
        objects: [root.sink, root.source, root.micNode].filter(x => x).concat(root.players, root.videoSources)
    }
}
