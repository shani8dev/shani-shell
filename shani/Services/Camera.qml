pragma Singleton
// The camera, with the system's own tools: libcamera's `cam` lists cameras and
// takes stills (a few frames so exposure settles, the last one kept, PPM →
// PNG), `qcam` is the live viewfinder, and video goes through PipeWire —
// GStreamer's pipewiresrc for the camera, the default microphone for sound,
// VP8 + Opus in WebM. libcamera reaches the cameras /dev/video cannot (Intel
// IPU6 and the like). The camera switch (Privacy.cameraEnabled) is respected.
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
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
    property bool open: false               // the Camera surface (Modules/Camera)
    property int selected: -1               // camera index; -1 = first
    property string mode: "photo"           // photo | video
    property bool withAudio: true           // record the microphone with video
    property int selfTimer: 3               // seconds before a photo; 0 = shoot now
    property string photoFormat: "png"      // png | jpg
    property string videoFormat: "webm"     // webm (.vp8) | mp4 (.h264)
    property var gallery: []                // [{ path, name, when }] newest-first

    function shutter() {
        if (mode === "photo") photo();
        else video();
    }
    // the viewfinder is a tracked process, not execDetached: its lifetime follows
    // Camera.open, and a camera change retargets it instead of orphaning qcam
    Process { id: viewfinder }
    function openViewfinder() {
        if (!root.open || Quickshell.env("SHANI_NO_VIEWFINDER")) return;
        viewfinder.running = false;
        viewfinder.command = ["sh", "-c", 'command -v qcam >/dev/null && exec qcam ${1:+-c $1}; exec flatpak run org.gnome.Snapshot', "sh", selected >= 0 ? String(selected) : ""];
        viewfinder.running = true;
    }
    function stopViewfinder() { viewfinder.running = false; }
    function openCamera() { refresh(); open = true; }
    function closeCamera() { open = false; stopViewfinder(); }
    onOpenChanged: if (root.open) openViewfinder()
    onSelectedChanged: if (root.open) openViewfinder()
    function scanGallery() { scanProc.running = true; }
    Process {
        id: scanProc
        command: ["sh", "-c", 'for d in "$1" "$2"; do [ -d "$d" ] && ls -t "$d" 2>/dev/null | sed "s|^|$d/|"; done | head -40', "sh", root.photosDir, root.videosDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                text.split("\n").forEach(p => { if (p.trim()) out.push({ path: p, name: p.split("/").pop(), when: isoOf(p) }); });
                root.gallery = out;
            }
        }
    }
    // captures are named "Photo|Video yyyy-MM-dd hh-mm-ss.ext" by stamp(); that
    // whole string is not a JS date, so pull out the numeric portion instead
    function isoOf(path) {
        const m = /(\d{4})-(\d{2})-(\d{2})[ -](\d{2})-(\d{2})-(\d{2})/.exec(path.split("/").pop());
        if (!m) return "";
        const d = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
        return isNaN(d.getTime()) ? "" : Qt.formatDateTime(d, "yyyy-MM-dd hh:mm:ss");
    }
    // delete a capture from the in-window gallery (gio trash, so it can come back)
    function trash(path) {
        if (!path)
            return;
        trashProc.command = ["gio", "trash", "--", path];
        trashProc.running = true;
        if (last === path) last = "";
    }
    Process { id: trashProc; onExited: root.scanGallery() }

    function refresh() { list.running = true; }
    function stamp() { return Qt.formatDateTime(new Date(), "yyyy-MM-dd hh-mm-ss"); }

    function photo() {
        if (phase !== "idle" || !available || !Privacy.cameraEnabled)
            return;
        countdown = selfTimer > 0 ? selfTimer : 0;
        if (countdown <= 0) { captureStill(); return; }   // timer off: shoot now
        phase = "counting";
        tick.restart();
    }
    // capture the still; png first, converted to jpg afterwards if asked for
    function captureStill() {
        tick.stop();
        root.phase = "capturing";
        root.last = root.photosDir + "/Photo " + root.stamp() + ".png";
        SystemSounds.play("camera-shutter");
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
                rm -rf "$d"', "sh", root.tool, String(root.selected >= 0 ? root.selected : (root.cameras[0] ? root.cameras[0].index : 0)), root.last];
            still.running = true;
    }
    // the countdown before a photo; with the timer off captureStill() runs directly
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown > 0)
                return;
            root.captureStill();
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
            if (root.photoFormat === "jpg") {
                const jpg = root.last.replace(/\.png$/, ".jpg");
                conv.command = ["ffmpeg", "-y", "-loglevel", "error", "-i", root.last, "-q:v", "2", jpg];
                conv.out = jpg;
                conv.running = true;
                return;
            }
            finishPhoto();
        }
    }
    // png -> jpg conversion for the picture-format choice
    Process {
        id: conv
        property string out: ""
        onExited: code => {
            if (code === 0 && root.out) {
                Quickshell.execDetached(["rm", "-f", "--", root.last]);   // drop the png, keep the jpg
                root.last = root.out;
            }
            finishPhoto();
        }
    }
    function finishPhoto() {
        offer.command = ["notify-send", "-a", "Camera", "-i", root.last, "-A", "open=Open", "-A", "lens=Read with Lens", "Photo taken", root.last.split("/").pop()];
        offer.running = true;
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
    // where video and sound come from: the camera's PipeWire node and the default
    // microphone; the tests point them at GStreamer's test pattern and tone
    property string videoSource: "pipewiresrc"
    property string audioSource: "pulsesrc"
    // cam -l's index (the picker's key) is not a PipeWire node id. Match the
    // selected camera to a video node by name; when nothing matches, leave
    // pipewiresrc unqualified so PipeWire falls back to its default camera.
    function selectedPwNodeId() {
        const idx = root.selected >= 0 ? root.selected : (root.cameras[0] ? root.cameras[0].index : -1);
        const cam = root.cameras.find(c => c.index === idx);
        if (!cam) return 0;
        const name = cam.name.toLowerCase();
        const nodes = Pipewire.nodes.values.filter(n => (n.type & PwNodeType.VideoSource) === PwNodeType.VideoSource);
        const hit = nodes.find(n => {
            const target = ((n.name || "") + " " + ((n.properties || {})["node.description"] || "")).toLowerCase();
            return name.length > 0 && target.indexOf(name) >= 0;
        });
        return hit ? hit.id : 0;
    }
    function videoSrc() {
        if (root.videoSource !== "pipewiresrc") return root.videoSource;   // test/source override
        const id = root.selectedPwNodeId();
        return id > 0 ? "pipewiresrc path=" + id : "pipewiresrc";
    }
    function video() {
        if (phase === "recording") {
            rec.signal(2);                // SIGINT: gst-launch -e finishes the file
            return;
        }
        if (phase !== "idle" || !available || !Privacy.cameraEnabled)
            return;
        const mp4 = videoFormat === "mp4";
        last = videosDir + "/Video " + stamp() + (mp4 ? ".mp4" : ".webm");
        // H.264/AAC in MP4 when asked for; otherwise VP8/Opus in WebM.
        // Encoders and sources are argv slots, never interpolated into the shell string.
        const venc = mp4 ? "x264enc tune=zerolatency" : "vp8enc deadline=1 cpu-used=8";
        const muxer = mp4 ? "mp4mux" : "webmmux";
        const aenc = mp4 ? "avenc_aac" : "opusenc";
        const mic = withAudio ? " $5 ! audioconvert ! $6 ! queue ! mux." : "";
        const videoSource = root.videoSrc();   // resolved pipewiresrc for the selected camera
        rec.command = ["sh", "-c", 'mkdir -p "${1%/*}" && exec gst-launch-1.0 -e $2 ! videoconvert ! queue ! $3 ! $4 name=mux ! filesink location="$1"' + mic,
                       "sh", last, videoSource, venc, muxer, audioSource, aenc];
        SystemSounds.play("camera-shutter");
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

    // the legacy Snapshot Flatpak launcher (kept for the handoff; the shell
    // camera surface is Modules/Camera, and its live preview is qcam)
    function openApp() {
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
    Connections { target: Privacy; function onCamerasChanged() { root.refresh(); } }   // a camera plugged in or out
}
