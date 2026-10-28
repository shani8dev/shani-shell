pragma Singleton
// Accessibility: a screen reader (Orca, over AT-SPI — the shell's own controls
// carry accessible names), large text (GNOME's text-scaling-factor, which apps
// follow; the shell scales its own type too), high contrast (Theme), and mono
// audio (a PipeWire remap sink summing both channels, made the default).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property bool screenReader: Settings.data.screenReader
    readonly property bool largeText: Settings.data.largeText
    readonly property bool monoAudio: Settings.data.monoAudio
    property bool hasOrca: false

    // Orca for as long as the switch is on
    Process {
        running: root.screenReader && root.hasOrca
        command: ["orca", "--replace"]
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v orca"]
        onExited: code => root.hasOrca = code === 0
    }
    // what GNOME's own switches set, so apps that read them agree
    Process {
        running: true
        command: ["sh", "-c", 'gsettings set org.gnome.desktop.a11y.applications screen-reader-enabled "$1"; gsettings set org.gnome.desktop.interface text-scaling-factor "$2"', "sh",
                  String(root.screenReader), root.largeText ? "1.25" : "1.0"]
        onCommandChanged: running = true
    }
    // mono audio: a remap sink over the current output, both channels the same
    Process {
        id: mono
        command: ["sh", "-c", root.monoAudio
            ? 'pactl list short modules | grep -q "sink_name=shani-mono" || { m=$(pactl get-default-sink); pactl load-module module-remap-sink sink_name=shani-mono master="$m" channels=2 channel_map=mono,mono sink_properties=device.description=Mono >/dev/null; pactl set-default-sink shani-mono; }'
            : 'for id in $(pactl list short modules | awk "/sink_name=shani-mono/{print \\$1}"); do pactl unload-module "$id"; done']
        onCommandChanged: running = true
        Component.onCompleted: running = true
    }
}
