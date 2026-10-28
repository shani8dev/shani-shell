pragma Singleton
// PipeWire through Quickshell's built-in client: default sink/source, volume,
// mute, output switching, and the privacy signal "something is recording".
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool ready: Pipewire.ready && sink !== null && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : true
    readonly property bool micMuted: source && source.audio ? source.audio.muted : true
    readonly property real micVolume: source && source.audio ? source.audio.volume : 0

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

    function setVolume(v) {
        if (!ready)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1.0, v));
    }
    function step(delta) {
        setVolume(volume + delta);
    }
    function toggleMute() {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }
    function toggleMic() {
        if (source && source.audio)
            source.audio.muted = !source.audio.muted;
    }
    function setMicVolume(v) {
        if (source && source.audio)
            source.audio.volume = Math.max(0, Math.min(1.0, v));
    }
    function useSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }
    function useSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }
    function nodeName(n) {
        return n ? (n.description || n.nickname || n.name) : "";
    }
    function streamName(n) {
        const p = n.properties;
        return p["application.name"] || p["media.name"] || n.name;
    }

    // Binding a node's audio properties requires tracking it.
    PwObjectTracker {
        objects: [root.sink, root.source].concat(root.players, root.videoSources)
    }
}
