pragma Singleton
// What a picture records about itself: the camera and the moment, from exiv2's
// EXIF read. Shown in the Files preview pane — a grid of thumbnails has nowhere
// to put it, and this is where a person checks a file before using it.
//
// exiv2 is optional: without it the preview simply shows no line.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_EXIV2_TOOL") || "exiv2"

    // the selected file, read here rather than pushed from the window
    readonly property string file: {
        const sel = Files.selected;
        if (!sel || sel.length !== 1) return "";
        const e = Files.entryFor(sel[0]);
        return e && !e.isDir ? e.path : "";
    }
    property string camera: ""
    property string date: ""
    property bool available: true

    onFileChanged: {
        camera = ""; date = "";
        if (!file || !/\.(jpe?g|tiff?|png|webp|heic|avif)$/i.test(file)) return;
        info.running = false;
        info.running = true;
    }

    Process {
        id: info
        // -Pv prints values only, one per line, in the order asked for
        command: ["sh", "-c", 'command -v "$1" >/dev/null 2>&1 || exit 3; "$1" -g Exif.Image.Make -g Exif.Image.Model -g Exif.Photo.DateTimeOriginal -Pv "$2" 2>/dev/null', "sh", root.tool, root.file]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").map(l => l.trim()).filter(l => l !== "");
                // Make and Model are separate values; one is often absent
                root.camera = lines.slice(0, 2).filter(l => l && l !== "0").join(" ");
                const d = lines.filter(l => /^\d{4}[:-]\d\d[:-]\d\d/.test(l))[0] || "";
                root.date = d.replace(/^(\d{4})[:-](\d\d)[:-](\d\d)[ T](\d\d):(\d\d).*/, "$1-$2-$3 $4:$5");
            }
        }
        onExited: code => { if (code === 3) root.available = false; }
    }
}