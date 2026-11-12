import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "FileFilter.js" as FileFilter

// One directory, and what is in it. The backend (bridge/files.py) watches the
// folder and re-lists it on every change, so a file made or removed
// elsewhere shows up here too; the listing is replaced wholesale rather
// than patched, so a rename cannot leave a stale row behind.
//
// The watch is a python process, alive only while this model is: it is
// started when a path is set and stopped when the model goes away.
QtObject {
    id: root

    property string path: ""
    property bool includeHidden: false
    property string sortKey: "name"
    property bool sortDesc: false
    property var filters: []        // extensions to keep, for a picker
    property string query: ""        // the search box: matched against the names

    readonly property ListModel entries: ListModel {}
    property bool loading: false
    property string error: ""
    property int total: 0

    property var _all: []            // every entry, before the search box
    property var _matcher: null

    // the backend (bridge/files.py); the service uses the same one
    readonly property string tool: Quickshell.env("SHANI_FILES_TOOL") || "/usr/lib/shani-shell/files.py"

    signal listed()

    onPathChanged: reload()
    onIncludeHiddenChanged: reload()
    onSortKeyChanged: reload()
    onSortDescChanged: reload()
    onFiltersChanged: reload()
    onQueryChanged: refilter()

    Component.onDestruction: root.watcher.running = false

    readonly property var watchCommand: {
        const args = ["python3", root.tool, "watch", root.path];
        if (root.includeHidden)
            args.push("--hidden");
        args.push("--sort=" + root.sortKey);
        if (root.sortDesc)
            args.push("--desc");
        if (root.filters && root.filters.length)
            args.push("--filter=" + root.filters.join(","));
        return args;
    }

    function reload() {
        root.error = "";
        root.loading = true;
        root.watcher.running = false;
        Qt.callLater(function () {
            root.watcher.command = root.watchCommand;
            root.watcher.running = true;
        });
    }

    // the whole folder again: the watch answers with the listing straight away
    function refresh() {
        root.reload();
    }

    function refilter() {
        root._matcher = root.query === "" ? null : FileFilter.compile(root.query);
        root.entries.clear();
        for (const e of root._all) {
            if (!FileFilter.matches(root._matcher, e))
                continue;
            root.entries.append(e);
        }
        root.total = root._all.length;
        root.listed();
    }

    function entryAt(index) {
        if (index < 0 || index >= root.entries.count)
            return null;
        return root.entries.get(index);
    }

    function indexOfPath(path) {
        for (let i = 0; i < root.entries.count; i++) {
            if (root.entries.get(i).path === path)
                return i;
        }
        return -1;
    }

    function applyLine(line) {
        const text = String(line || "").trim();
        if (!text)
            return;
        let r = {};
        try {
            r = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (r.error) {
            root.error = r.error;
            root.loading = false;
            root._all = [];
            root.entries.clear();
            return;
        }
        root.error = "";
        root.loading = false;
        root._all = r.entries || [];
        root.refilter();
    }

    // the watcher: the folder, watched. It re-lists on every change, so the
    // model is replaced wholesale rather than patched.
    property Process watcher: Process {
        stdout: SplitParser { onRead: line => root.applyLine(line) }
        onExited: (code) => {
            // the folder is gone, or the watch could not be set up: the panel
            // asks for a fresh listing, which reports the error properly
            if (code !== 0 && root.path !== "")
                root.refresh();
        }
    }
}
