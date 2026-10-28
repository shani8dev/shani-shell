pragma Singleton
// Outputs from niri (`niri msg -j outputs`), and the two things a person
// changes most: scale, and mirroring one screen onto another (wl-mirror, for
// presenting). Layout and modes stay with niri's config / wdisplays.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var outputs: []        // [{ name, label, scale }]
    property bool canMirror: false
    property bool mirroring: mirror.running

    function refresh() { list.running = true; }
    function setScale(name, scale) {
        Quickshell.execDetached(["niri", "msg", "output", name, "scale", String(scale)]);
        settle.restart();
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

    Process { id: mirror }
    Timer { id: settle; interval: 600; onTriggered: root.refresh() }
    Process {
        id: list
        running: true
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    root.outputs = Object.keys(o).sort().map(k => ({
                        name: k,
                        label: [o[k].make, o[k].model].filter(x => x && x !== "Unknown").join(" ") || k,
                        scale: o[k].logical ? o[k].logical.scale : 1
                    }));
                } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v wl-mirror"]
        onExited: code => root.canMirror = code === 0
    }
}
