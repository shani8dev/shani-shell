pragma Singleton
// The camera, with the system's own tools: libcamera's `cam` lists cameras and
// takes stills (a few frames so exposure settles, the last one kept, PPM →
// PNG), `qcam` is the live viewfinder, and video goes through PipeWire —
// GStreamer's pipewiresrc for the camera, the default microphone for sound,
// VP8 + Opus in WebM. libcamera reaches the cameras /dev/video cannot (Intel
// IPU6 and the like). The camera switch (Privacy.cameraEnabled) is respected.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_CAM_TOOL") || "cam"
    property var cameras: []              // [{ index, name }]
    readonly property bool available: cameras.length > 0
    property int countdown: 0             // 3, 2, 1 before a photo
    property string phase: "idle"         // idle | counting | capturing | recording
    property string last: ""              // the last photo or video
    property int seconds: 0
    readonly property string elapsed: Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    readonly property string photosDir: (Quickshell.env("XDG_PICTURES_DIR") || Quickshell.env("HOME") + "/Pictures") + "/Camera"
    readonly property string videosDir: (Quickshell.env("XDG_VIDEOS_DIR") || Quickshell.env("HOME") + "/Videos") + "/Camera"

    function refresh() { list.running = true; }
    function stamp() { return Qt.formatDateTime(new Date(), "yyyy-MM-dd hh-mm-ss"); }

    function photo() {
        if (phase !== "idle" || !available || !Privacy.cameraEnabled)
            return;
        countdown = 3;
        phase = "counting";
        tick.restart();
    }
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown > 0)
                return;
            stop();
            root.phase = "capturing";
            root.last = root.photosDir + "/Photo " + root.stamp() + ".png";
            still.command = ["sh", "-c", 'd="${XDG_RUNTIME_DIR:-/tmp}/shani-cam"; rm -rf "$d"; mkdir -p "$d" "${3%/*}" &&
                "$1" -c "$2" -C 8 -s role=still,pixelformat=RGB888 -F "$d/f#.ppm" >/dev/null 2>&1
                f=$(ls "$d"/*.ppm 2>/dev/null | sort | tail -1); [ -n "$f" ] || exit 3
                python3 - "$f" "$3" <<"PY"
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
# P6 header: magic, width, height, maxval, each after whitespace (comments allowed)
fields, i = [], 0
while len(fields) < 4:
    while data[i:i + 1].isspace(): i += 1
    if data[i:i + 1] == b"#":
        i = data.index(b"\\n", i); continue
    j = i
    while not data[j:j + 1].isspace(): j += 1
    fields.append(data[i:j]); i = j
i += 1
w, h = int(fields[1]), int(fields[2])
px = data[i:i + w * h * 3]
raw = b"".join(b"\\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
chunk = lambda t, b: struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))
open(sys.argv[2], "wb").write(b"\\x89PNG\\r\\n\\x1a\\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                              + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
PY
                rm -rf "$d"', "sh", root.tool, String(root.cameras[0].index), root.last];
            still.running = true;
        }
    }
    Process {
        id: still
        onExited: code => {
            root.phase = "idle";
            if (code !== 0) {
                Quickshell.execDetached(["notify-send", "-a", "Camera", "-i", "camera-photo", "No photo taken", "The camera did not give a picture."]);
                return;
            }
            offer.command = ["notify-send", "-a", "Camera", "-i", root.last, "-A", "open=Open", "-A", "lens=Read with Lens", "Photo taken", root.last.split("/").pop()];
            offer.running = true;
        }
    }
    // the photo's notification: open it, or read text and codes in it
    Process {
        id: offer
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim();
                if (a === "open")
                    Qt.openUrlExternally("file://" + root.last);
                else if (a === "lens")
                    Lens.readFile(root.last);
            }
        }
    }

    // ---- video ---------------------------------------------------------------
    function video() {
        if (phase === "recording") {
            rec.signal(2);                // SIGINT: gst-launch -e finishes the file
            return;
        }
        if (phase !== "idle" || !available || !Privacy.cameraEnabled)
            return;
        last = videosDir + "/Video " + stamp() + ".webm";
        rec.command = ["sh", "-c", 'mkdir -p "${1%/*}" && exec gst-launch-1.0 -e pipewiresrc ! videoconvert ! queue ! vp8enc deadline=1 cpu-used=8 ! webmmux name=mux ! filesink location="$1" pulsesrc ! audioconvert ! opusenc ! queue ! mux.', "sh", last];
        seconds = 0;
        phase = "recording";
        rec.running = true;
    }
    Process {
        id: rec
        onExited: code => {
            root.phase = "idle";
            Quickshell.execDetached(["notify-send", "-a", "Camera", "-i", "camera-video", code === 0 ? "Video saved" : "Video stopped", root.last.split("/").pop()]);
        }
    }
    Timer { running: root.phase === "recording"; interval: 1000; repeat: true; onTriggered: root.seconds++ }

    // the live viewfinder
    // the viewfinder: GNOME Snapshot (a Flatpak in the image; photos, video,
    // QR codes), libcamera's qcam without it
    function open() {
        Quickshell.execDetached(["sh", "-c", "flatpak info org.gnome.Snapshot >/dev/null 2>&1 && exec flatpak run org.gnome.Snapshot; exec qcam"]);
    }

    // "1: 'Integrated Camera' (\_SB_.PCI0...)"
    Process {
        id: list
        running: true
        command: ["sh", "-c", 'command -v "$1" >/dev/null && "$1" -l 2>/dev/null', "sh", root.tool]
        stdout: StdioCollector {
            onStreamFinished: root.cameras = text.split("\n").map(l => /^(\d+): '([^']*)'/.exec(l.trim())).filter(m => m).map(m => ({ index: parseInt(m[1]), name: m[2] }))
        }
    }
    Timer { interval: 10000; running: true; repeat: true; onTriggered: root.refresh() }   // a camera plugged in
}
