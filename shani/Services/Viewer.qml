pragma Singleton
// Pictures, in the shell (Viewer): one image at a time, its folder sorted
// around it (next/prev wrap), wheel zoom and 90° rotates. Shown by
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
        file = path;
        const dir = path.substring(0, path.lastIndexOf("/")) || Quickshell.env("HOME") || "/";
        listProc.command = ["sh", "-c", 'ls -1 -- "$1" 2>/dev/null | sort', "sh", dir];
        listProc.running = true;
    }
    function close() {
        file = "";
        list = [];
        index = -1;
        zoom = 1.0;
        rotation = 0;
    }
    function next() {
        if (!list.length || index < 0)
            return;
        index = (index + 1) % list.length;
        file = list[index];
        zoom = 1.0;
        rotation = 0;
    }
    function prev() {
        if (!list.length || index < 0)
            return;
        index = (index - 1 + list.length) % list.length;
        file = list[index];
        zoom = 1.0;
        rotation = 0;
    }
    // the same words the shell uses for files elsewhere
    function previous() { prev(); }

    function setZoom(z) { zoom = Math.max(0.1, Math.min(8.0, z)); }
    function zoomIn() { setZoom(zoom * 1.25); }
    function zoomOut() { setZoom(zoom / 1.25); }
    function zoomReset() { zoom = 1.0; }
    function rotate() { rotation = (rotation + 90) % 360; }

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
}
