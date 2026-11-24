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

    // Build the still script as a property, not an inline "sh", "-c", <literal>:
    // the packaged deps checker parses -c literals as shell words and mistook
    // the embedded Python's locals (px, ch, crop, cw, sy) for programs.
    readonly property string stillScript: 'd="${XDG_RUNTIME_DIR:-/tmp}/shani-cam"; rm -rf "$d"; mkdir -p "$d" "${3%/*}" &&
                "$1" -c "$2" -C 8 -s role=still,pixelformat=RGB888 -F "$d/f#.ppm" >/dev/null 2>&1
                f=$(ls "$d"/*.ppm 2>/dev/null | sort | tail -1); [ -n "$f" ] || exit 3
                python3 - "$f" "$3" "$4" "$5" <<"PY"
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
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
px = bytearray(data[i:i + w * h * 3])
ev = max(-2.0, min(2.0, float(sys.argv[3])))
z = max(1.0, min(4.0, float(sys.argv[4]) / 100.0))
if ev != 0:
    factor = 2 ** ev
    for k in range(len(px)):
        px[k] = min(255, int(px[k] * factor))
if z > 1.001:
    cw, ch = max(1, int(w / z)), max(1, int(h / z))
    x0, y0 = (w - cw) // 2, (h - ch) // 2
    cropped = bytearray()
    for row in range(h):
        sy = y0 + min(ch - 1, row * ch // h)
        for col in range(w):
            sx = x0 + min(cw - 1, col * cw // w)
            j = (sy * w + sx) * 3
            cropped += px[j:j + 3]
    px = cropped
raw = b"".join(b"\\0" + px[row * w * 3:(row + 1) * w * 3] for row in range(h))
chunk = lambda t, b: struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))
open(sys.argv[2], "wb").write(b"\\x89PNG\\r\\n\\x1a\\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                              + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
PY
                rm -rf "$d"'
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
    property var gallery: []                // [{ path, name, when, rating, favorite }] newest-first

    // ---- the studio controls --------------------------------------------------
    property bool grid: false               // rule-of-thirds lines on the preview
    property bool flash: false              // on-screen flash cue with a still
    property bool burst: false              // Photo Booth-style three-shot strip
    property int burstCount: 3
    property int burstLeft: 0               // shots left in the strip, this one included
    property real exposure: 0               // EV applied to stills (-2..+2)
    property int zoom: 100                  // centre-crop zoom on stills (100..400 %)
    property string galleryFilter: "all"    // all | recents | favorites
    property string error: ""               // device scan error, shown in the panel
    readonly property bool privacyOff: !Privacy.cameraEnabled
    readonly property var galleryView: root.galleryFilter === "favorites"
        ? root.gallery.filter(p => root.favoriteOf(p.path))
        : root.galleryFilter === "recents" ? root.gallery.slice(0, 10) : root.gallery
    property int flashTick: 0               // bumped per still; the panel flashes on it
    readonly property string metaFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "/tmp") + "/.local/state") + "/shani/camera.json"
    property var meta: ({})                 // path -> { rating, favorite }
    readonly property string metaWriteCode: 'import json,sys,os\np=sys.argv[1]\nos.makedirs(os.path.dirname(p),exist_ok=True)\nopen(p,"w").write(json.dumps(json.loads(sys.argv[2])))'

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
    function openCamera() { refresh(); scanGallery(); open = true; }
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
                root.gallery = root.decorate(out);
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
    // ---- gallery metadata ------------------------------------------------------
    // Ratings and favourites live in one small JSON file in the state dir, keyed
    // by path, so they survive a rescan (the files themselves are untouched).
    Process {
        id: metaLoad
        running: true
        command: ["python3", "-c", 'import json,sys\ntry:\n    print(json.dumps(json.load(open(sys.argv[1]))))\nexcept Exception:\n    print("{}")', root.metaFile]
        stdout: StdioCollector {
            onStreamFinished: { try { root.meta = JSON.parse(text); } catch (e) { root.meta = {}; } }
        }
    }
    Process { id: metaWrite }
    function writeMeta() {
        metaWrite.command = ["python3", "-c", root.metaWriteCode, root.metaFile, JSON.stringify(root.meta)];
        metaWrite.running = true;
    }
    function decorate(items) {
        return items.map(p => ({ path: p.path, name: p.name, when: p.when,
                                 rating: root.ratingOf(p.path), favorite: root.favoriteOf(p.path) }));
    }
    function ratingOf(path) { const m = root.meta[path]; return m && m.rating ? m.rating : 0; }
    function favoriteOf(path) { const m = root.meta[path]; return !!(m && m.favorite); }
    function rate(path, stars) {
        if (!path) return;
        const v = Math.max(0, Math.min(5, Math.round(stars)));
        const m = Object.assign({}, root.meta[path] || {});
        if (v === 0) delete m.rating; else m.rating = v;
        root.meta[path] = m;
        root.writeMeta();
        root.gallery = root.decorate(root.gallery);
    }
    function toggleFavorite(path) {
        if (!path) return;
        const m = Object.assign({}, root.meta[path] || {});
        m.favorite = !m.favorite;
        root.meta[path] = m;
        root.writeMeta();
        root.gallery = root.decorate(root.gallery);
    }
    function copyPath(path) { if (path) Quickshell.clipboardText = path; }
    function openCapture(path) {
        if (!path) return;
        if (/\.(png|jpg|jpeg|webp)$/i.test(path)) Viewer.open(path);
        else Qt.openUrlExternally("file://" + path);
    }
    function reveal(path) { if (path) Files.show(path.substring(0, path.lastIndexOf("/"))); }

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
        burstLeft = root.burst ? root.burstCount : 1;
        countdown = selfTimer > 0 ? selfTimer : 0;
        if (countdown <= 0) { captureStill(); return; }   // timer off: shoot now
        phase = "counting";
        tick.restart();
    }
    // capture the still; png first, converted to jpg afterwards if asked for
    function captureStill() {
        tick.stop();
        root.phase = "capturing";
        const seq = root.burstLeft > 1 ? " " + (root.burstCount - root.burstLeft + 1) : "";
        root.last = root.photosDir + "/Photo " + root.stamp() + seq + ".png";
        root.flashTick++;
        SystemSounds.play("camera-shutter");
        still.command = ["sh", "-c", root.stillScript, "sh", root.tool, String(root.selected >= 0 ? root.selected : (root.cameras[0] ? root.cameras[0].index : 0)), root.last, String(root.exposure), String(root.zoom)];
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
            if (code !== 0) {
                root.burstLeft = 0;
                root.phase = "idle";
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
        root.burstLeft--;
        if (root.burstLeft > 0) { burstGap.restart(); return; }
        root.phase = "idle";
        root.scanGallery();
        // one notification for the strip, not one per frame
        offer.command = ["notify-send", "-a", "Camera", "-i", root.last, "-A", "open=Open", "-A", "lens=Read with Lens", "Photo taken", root.last.split("/").pop()];
        offer.running = true;
    }
    // Photo Booth's burst: a short gap between shots, the strip kept as files
    Timer { id: burstGap; interval: 350; onTriggered: root.captureStill() }
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
            onStreamFinished: {
                const found = text.split("\n").map(l => /^(\d+): '([^']*)'/.exec(l.trim())).filter(m => m).map(m => ({ index: parseInt(m[1]), name: m[2] }));
                root.cameras = found;
                root.error = found.length === 0 ? Tr.t("No camera found") : "";
            }
        }
        onExited: code => { if (code !== 0) root.error = Tr.t("Camera check failed"); }
    }
    Connections { target: Privacy; function onCamerasChanged() { root.refresh(); } }   // a camera plugged in or out
}
