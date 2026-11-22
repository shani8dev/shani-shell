pragma Singleton
// What a picture records about itself: the camera, the moment and the exposure,
// from exiv2's EXIF read. Shown in the Files preview pane and in Photos' details
// panel; a caller can also point it at a file explicitly with read(path).
//
// exiv2 is optional: without it the preview simply shows no line.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_EXIV2_TOOL") || "exiv2"

    // the selected file, read here rather than pushed from the window. A caller
    // (Photos) can override it without touching the Files selection.
    property string fileOverride: ""
    readonly property string file: {
        if (fileOverride) return fileOverride;
        const sel = Files.selected;
        if (!sel || sel.length !== 1) return "";
        const e = Files.entryFor(sel[0]);
        return e && !e.isDir ? e.path : "";
    }
    function read(path) { fileOverride = path || ""; }

    // key -> human label. -pv prints "key value" per line, so a missing tag
    // cannot shift the following ones the way the old values-only read did.
    readonly property var tags: [
        ["Exif.Image.Make", "Make"],
        ["Exif.Image.Model", "Camera"],
        ["Exif.Photo.LensModel", "Lens"],
        ["Exif.Photo.DateTimeOriginal", "Taken"],
        ["Exif.Photo.ExposureTime", "Exposure"],
        ["Exif.Photo.FNumber", "Aperture"],
        ["Exif.Photo.ISOSpeedRatings", "ISO"],
        ["Exif.Photo.FocalLength", "Focal length"],
        ["Exif.Image.ImageWidth", "Width"],
        ["Exif.Image.ImageLength", "Height"]
    ]
    property var details: []          // [{ label, value }] for the details panel
    property string camera: ""
    property string date: ""
    property bool available: true

    onFileChanged: {
        camera = ""; date = ""; details = [];
        if (!file || !/\.(jpe?g|tiff?|png|webp|heic|avif)$/i.test(file)) return;
        info.running = false;
        info.running = true;
    }

    Process {
        id: info
        // -pv: key and value, one tag per line, in the order asked for
        command: ["sh", "-c", 'command -v "$1" >/dev/null 2>&1 || exit 3; "$1" -g Exif.Image.Make -g Exif.Image.Model -g Exif.Photo.LensModel -g Exif.Photo.DateTimeOriginal -g Exif.Photo.ExposureTime -g Exif.Photo.FNumber -g Exif.Photo.ISOSpeedRatings -g Exif.Photo.FocalLength -g Exif.Image.ImageWidth -g Exif.Image.ImageLength -pv "$2" 2>/dev/null', "sh", root.tool, root.file]
        stdout: StdioCollector {
            onStreamFinished: {
                const vals = {};
                for (const line of text.split("\n")) {
                    const m = line.trim().match(/^(Exif\.\S+)\s+(.*)$/);
                    if (m) vals[m[1]] = m[2].trim();
                }
                const out = [];
                for (const t of root.tags)
                    if (vals[t[0]]) out.push({ label: Tr.t(t[1]), value: vals[t[0]] });
                root.details = out;
                root.camera = [vals["Exif.Image.Make"], vals["Exif.Image.Model"]].filter(Boolean).join(" ");
                const d = vals["Exif.Photo.DateTimeOriginal"] || "";
                root.date = d.replace(/^(\d{4})[:-](\d\d)[:-](\d\d)[ T](\d\d):(\d\d).*/, "$1-$2-$3 $4:$5");
            }
        }
        onExited: code => { if (code === 3) root.available = false; }
    }
}
