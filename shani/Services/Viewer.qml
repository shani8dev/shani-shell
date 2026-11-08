pragma Singleton
// Pictures, in the shell (Viewer): Loupe parity — one image at a time, its
// folder sorted around it (next/prev wrap), zoom to cursor, fit / 100% /
// 200%, rotate + flip, slideshow mode, thumbnail strip, EXIF-aware rotation,
// copy path, open-with, delete-to-trash and batch grid mode. Shown by
// Modules/Viewer/Viewer.qml until closed.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string file: ""               // the picture on screen, while open
    property var list: []                   // the folder's pictures, sorted
    property int index: -1                  // where `file` sits in `list`
    property real zoom: 1.0                 // 0.1 .. 8.0, wheel and keys
    property int rotation: 0                // 0 | 90 | 180 | 270
    property real panX: 0                   // drag offset (px, image-space) for zoom-to-cursor
    property real panY: 0
    property bool flipH: false              // mirror horizontally
    property bool flipV: false              // mirror vertically
    property string zoomMode: "fit"         // fit | 100 | 200 | custom — fit/100%/200%
    property bool slideshow: false           // slideshow mode (Timer below)
    property bool gridMode: false            // batch grid mode (folder as a grid)
    property bool showThumbs: true           // thumbnail strip visibility
    property int exifRotation: 0            // rotation implied by EXIF Orientation (274)
    property string exifOrientation: ""      // raw EXIF Orientation value, for the tests
    property string lastCopied: ""          // last path copied to the clipboard
    property string lastAction: ""          // open-with / trash result, for the tests
    property string trashLast: ""           // last file moved to trash

    readonly property bool shown: file !== ""
    readonly property string name: file === "" ? "" : file.split("/").pop()
    readonly property string position: list.length > 0 && index >= 0 ? (index + 1) + " / " + list.length : ""

    function isImage(p) {
        return /^(png|jpe?g|webp|avif|gif|bmp|tiff?|heic|heif|svg)$/i.test((p.split(".").pop() || ""));
    }

    function open(path) {
        if (!path)
            return;
        zoom = 1.0;
        rotation = 0;
        panX = 0;
        panY = 0;
        flipH = false;
        flipV = false;
        zoomMode = "fit";
        slideshow = false;
        gridMode = false;
        showThumbs = true;
        exifRotation = 0;
        exifOrientation = "";
        file = path;
        Ui.viewer = true;
        const dir = path.substring(0, path.lastIndexOf("/")) || Quickshell.env("HOME") || "/";
        listProc.command = ["sh", "-c", 'ls -1 -- "$1" 2>/dev/null | sort', "sh", dir];
        listProc.running = true;
        applyExif();
    }
    function close() {
        slideshow = false;
        gridMode = false;
        file = "";
        list = [];
        index = -1;
        zoom = 1.0;
        rotation = 0;
        panX = 0;
        panY = 0;
        flipH = false;
        flipV = false;
        Ui.viewer = false;
    }
    function next() {
        if (!list.length || index < 0)
            return;
        index = (index + 1) % list.length;
        file = list[index];
        _resetTransform();
        applyExif();
    }
    function prev() {
        if (!list.length || index < 0)
            return;
        index = (index - 1 + list.length) % list.length;
        file = list[index];
        _resetTransform();
        applyExif();
    }
    // the same words the shell uses for files elsewhere
    function previous() { prev(); }
    function goToIndex(i) {
        if (i < 0 || i >= list.length)
            return;
        index = i;
        file = list[i];
        _resetTransform();
        applyExif();
    }
    function _resetTransform() {
        zoom = 1.0;
        rotation = 0;
        panX = 0;
        panY = 0;
        flipH = false;
        flipV = false;
        zoomMode = "fit";
        exifRotation = 0;
        exifOrientation = "";
    }

    // ---- zoom: to cursor, fit / 100% / 200% --------------------------------
    function setZoom(z) {
        zoom = Math.max(0.1, Math.min(8.0, z));
        if (zoomMode !== "custom")
            zoomMode = "custom";
    }
    function zoomIn() { setZoom(zoom * 1.25); }
    function zoomOut() { setZoom(zoom / 1.25); }
    function zoomReset() { zoom = 1.0; panX = 0; panY = 0; zoomMode = "fit"; }
    function zoomFit() { zoom = 1.0; panX = 0; panY = 0; zoomMode = "fit"; }
    function zoomActual() { zoom = 1.0; panX = 0; panY = 0; zoomMode = "100"; }
    function zoom200() { zoom = 2.0; panX = 0; panY = 0; zoomMode = "200"; }
    function setZoomMode(m) {
        if (m === "fit") zoomFit();
        else if (m === "100" || m === "actual") zoomActual();
        else if (m === "200") zoom200();
        else zoomMode = m;
    }
    // zoom to cursor (Loupe parity): keep the image point under (cx, cy)
    // where it is. cx/cy are px from the viewport's top-left, vw/vh its size.
    function zoomToCursor(cx, cy, factor, vw, vh) {
        if (!vw || !vh || vw <= 0 || vh <= 0) {
            setZoom(zoom * (factor || 1));
            zoomMode = "custom";
            return;
        }
        const old = zoom;
        const nw = Math.max(0.1, Math.min(8.0, zoom * (factor || 1)));
        if (nw === old)
            return;
        const mx = cx - vw / 2, my = cy - vh / 2;
        // the image point under the cursor, in image-space, stays under it
        panX = mx * (1 - nw / old) + panX * (nw / old);
        panY = my * (1 - nw / old) + panY * (nw / old);
        zoom = nw;
        zoomMode = "custom";
    }
    function panBy(dx, dy) { panX += dx; panY += dy; }

    // ---- rotate + flip ------------------------------------------------------
    function rotate() { rotation = (rotation + 90) % 360; }
    function rotateCCW() { rotation = (rotation - 90 + 360) % 360; }
    function toggleFlipH() { flipH = !flipH; }
    function toggleFlipV() { flipV = !flipV; }
    function flipHorizontal() { toggleFlipH(); }
    function flipVertical() { toggleFlipV(); }

    // ---- slideshow / grid / thumbnails --------------------------------------
    function toggleSlideshow() { slideshow = !slideshow; }
    function toggleGrid() { gridMode = !gridMode; }
    function toggleThumbs() { showThumbs = !showThumbs; }

    // ---- actions: copy path, open-with, trash -------------------------------
    function copyPath() {
        if (!file)
            return;
        Quickshell.clipboardText = file;
        lastCopied = file;
        lastAction = "copied " + file;
    }
    function openWith(appId) {
        if (!file)
            return;
        if (appId)
            Ui.openFilesWith(appId, [file]);
        else
            Quickshell.execDetached(["gio", "open", root.file]);
        lastAction = "open-with " + (appId || "default") + " " + file;
    }
    function trash() {
        if (!file)
            return;
        const doomed = file;
        trashProc.command = ["gio", "trash", "--", doomed];
        trashProc.running = true;
        trashLast = doomed;
        lastAction = "trashed " + doomed;
        // optimistic: drop it from the folder and step on immediately
        const at = list.indexOf(doomed);
        if (at >= 0) {
            list = list.filter(p => p !== doomed);
            if (!list.length) {
                close();
                return;
            }
            index = Math.min(at, list.length - 1);
            file = list[index];
            _resetTransform();
            applyExif();
        } else {
            close();
        }
    }

    // ---- EXIF-aware rotation -------------------------------------------------
    // EXIF Orientation (tag 274): 3 -> 180°, 6 -> 90°, 8 -> 270° (the phone
    // portrait cases). Read with Pillow when there, else ImageMagick's
    // identify -format; linked EXIF stays the initial view (R still turns).
    function applyExif() {
        if (!file)
            return;
        exifProc.command = ["sh", "-c", 'python3 -c \'from PIL import Image; import sys; im=Image.open(sys.argv[1]); print(im.getexif().get(274, 1))\' "$1" 2>/dev/null || magick identify -format "%[EXIF:Orientation]" "$1" 2>/dev/null || identify -format "%[EXIF:Orientation]" "$1" 2>/dev/null || echo 1', "sh", root.file];
        exifProc.running = true;
    }
    function exifToRotation(o) {
        const n = parseInt(o);
        if (n === 3) return 180;
        if (n === 6) return 90;
        if (n === 8) return 270;
        return 0;
    }

    Timer {
        interval: 3500
        running: root.slideshow && root.shown && root.list.length > 1
        repeat: true
        onTriggered: root.next()
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                // `ls` prints bare names; the folder is the file's own, so
                // rebuild full paths and sort them (what the viewer walks)
                const dir = root.file.substring(0, root.file.lastIndexOf("/"));
                const items = text.trim().split("\n")
                    .filter(s => s)
                    .map(s => dir === "" ? s : dir + "/" + s)
                    .filter(p => root.isImage(p))
                    .sort((a, b) => a.localeCompare(b));
                root.list = items;
                root.index = items.indexOf(root.file);
                if (root.index < 0 && items.length) {
                    root.list = [root.file].concat(items);
                    root.index = 0;
                }
            }
        }
    }

    Process {
        id: exifProc
        stdout: StdioCollector {
            onStreamFinished: {
                const o = text.trim().split("\n")[0] || "1";
                root.exifOrientation = String(o);
                const deg = root.exifToRotation(o);
                root.exifRotation = deg;
                // only the initial view obeys EXIF: once the person rotated,
                // leave it (rotation is already their choice, tracked by them)
                if (deg !== 0 && root.rotation === 0)
                    root.rotation = deg;
            }
        }
    }
    Process { id: trashProc }
}
