pragma Singleton
// FilePicker: choose a file or a folder, in the shell itself. The native
// dialog (a portal) held the whole shell while D-Bus waited for it, and it
// looked like every other app's; this one is the shell's own, and it waits
// for nothing but the folder it is showing.
//
// The listing comes from Common/FileDirectory.qml, which watches the folder
// through bridge/files.py. One picker at a time: whoever asks for it is the
// one who gets the answer, so the caller passes a function to call back.
//
//   FilePicker.open({ mode: "folder", title: "...", onPicked: paths => ... })
//   FilePicker.open({ mode: "open", filters: ["jpg", "png"], multiple: true })
//   FilePicker.open({ mode: "save", defaultName: "untitled.txt" })
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root

    property bool shown: false
    property string mode: "open"          // open | save | folder
    property var filters: []             // the extensions to show, without the dot
    property bool multiple: false
    property string defaultName: ""
    property string startPath: ""
    property string title: ""
    property var onPicked: null           // (paths) => void
    property var onCancelled: null

    property string path: ""              // the folder on screen
    property var selected: []             // the chosen paths
    property string typedName: ""         // the name typed, in save mode
    property string error: ""
    property var lastPicked: []         // what the last chooser answered (for `state`)

    readonly property string home: Quickshell.env("HOME") || "/home"
    readonly property bool canAccept: {
        if (root.mode === "save")
            return Files.validName(root.typedName);
        if (root.mode === "folder")
            return root.path !== "";
        // open: a file, not a folder - a folder is walked into
        return root.selected.some(p => {
            const e = dir.entryAt(dir.indexOfPath(p));
            return !e || !e.isDir;
        });
    }

    // the folder being shown
    FileDirectory {
        id: dir
        includeHidden: Files.showHidden
        sortKey: Files.sortKey
        sortDesc: Files.sortDesc
        onListed: root.sync()
    }

    // what the surface shows
    readonly property var directory: dir
    readonly property var directoryEntries: dir.entries

    function sync() {
        const paths = [];
        for (let i = 0; i < dir.entries.count; i++)
            paths.push(dir.entries.get(i).path);
        root._paths = paths;
    }

    property var _paths: []

    function open(opts) {
        const o = opts || {};
        root.mode = o.mode || "open";
        root.filters = o.filters || [];
        root.multiple = o.multiple === true;
        root.defaultName = o.defaultName || "";
        root.startPath = o.startPath || "";
        root.title = o.title || "";
        root.onPicked = o.onPicked || null;
        root.onCancelled = o.onCancelled || null;
        root.selected = [];
        root.error = "";
        root.typedName = root.defaultName;
        dir.filters = root.filters;
        dir.path = Files.normalize(o.startPath || "") || root.home;
        root.path = dir.path;
        Files.loadPlaces();
        root.shown = true;
    }

    function close() {
        root.shown = false;
    }

    function cancel() {
        const cb = root.onCancelled;
        root.shown = false;
        root.onPicked = null;
        root.onCancelled = null;
        if (cb)
            cb();
    }

    function accept() {
        if (!root.canAccept)
            return;
        const cb = root.onPicked;
        const paths = root.result();
        root.lastPicked = paths;
        root.shown = false;
        root.onPicked = null;
        root.onCancelled = null;
        if (cb)
            cb(paths);
    }

    // what the caller gets
    function result() {
        if (root.mode === "save")
            return [Files.join(root.path, root.typedName.trim())];
        if (root.mode === "folder") {
            const dirs = root.selected.filter(p => {
                const e = dir.entryAt(dir.indexOfPath(p));
                return e && e.isDir;
            });
            return [dirs.length === 1 ? dirs[0] : root.path];
        }
        const files = root.selected.filter(p => {
            const e = dir.entryAt(dir.indexOfPath(p));
            return !e || !e.isDir;
        });
        return root.multiple ? files : files.slice(0, 1);
    }

    // ---- navigating -----------------------------------------------------------
    function go(at) {
        const p = Files.normalize(at || "");
        if (p === "")
            return;
        dir.path = p;
        root.path = p;
        root.selected = [];
    }

    function up() {
        const parent = Files.parentOf(root.path);
        if (parent !== "")
            go(parent);
    }

    // ---- the selection ---------------------------------------------------------
    function isSelected(p) { return root.selected.indexOf(p) >= 0; }

    function select(p, mode) {
        if (!p)
            return;
        // the range runs from where the pointer was, not from where it lands
        const anchor = root.selected.length ? root.selected[root.selected.length - 1] : "";
        if (mode === "toggle") {
            root.selected = root.isSelected(p) ? root.selected.filter(x => x !== p) : root.selected.concat([p]);
            return;
        }
        if (mode === "range" && anchor !== "") {
            const from = root._paths.indexOf(anchor);
            const to = root._paths.indexOf(p);
            if (from >= 0 && to >= 0) {
                const lo = Math.min(from, to);
                const hi = Math.max(from, to);
                root.selected = root._paths.slice(lo, hi + 1);
                return;
            }
        }
        root.selected = [p];
    }

    // a folder is walked into, a file is chosen
    function activate(p) {
        const e = dir.entryAt(dir.indexOfPath(p));
        if (e && e.isDir) {
            go(p);
            return;
        }
        if (root.mode === "folder")
            return;
        if (root.mode === "save") {
            root.typedName = e ? e.name : root.typedName;
            return;
        }
        root.select(p, "single");
        root.accept();
    }
}
