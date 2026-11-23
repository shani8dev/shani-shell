pragma Singleton
// The text editor's documents (Modules/TextEditor shows them): what is open,
// which one is in front, what has changed since it was read or saved.
//
// They live here and not in the panel because the panel is made when opened
// and gone when closed (shell.qml's LazyLoader): Escape, a click outside or
// another surface opening would otherwise throw away what was typed. Closing
// the editor keeps every document; an unsaved one is still there, marked,
// the next time it opens.
//
// Saving never leaves half a file: the text goes to a temporary file beside
// the real one, takes the real one's permissions, and is renamed over it. A
// link is followed, so the file it points at is the one written. Line endings
// are kept as they were read (a CRLF file stays CRLF).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    // [{ path, name, text, eol, modified, readOnly }] - a new array whenever a
    // document is added, removed, renamed or its "modified" mark flips, so
    // the tab row follows; typing only changes `text` inside one
    property var docs: []
    property int active: -1
    readonly property var current: active >= 0 && active < docs.length ? docs[active] : null
    readonly property int unsaved: docs.filter(d => d.modified).length
    property string error: ""             // why the last open or save did not happen
    property string lastSaved: ""         // the path last written (for `state`)
    property int goToLine: 0              // a line to show once the document is on screen (+LINE)
    property bool saving: false
    // undo/redo state of the document in front (arrays live on each doc)
    property int undoCount: 0
    property int redoCount: 0
    readonly property bool canUndo: root.undoCount > 0
    readonly property bool canRedo: root.redoCount > 0
    // bumped when the text on screen has to be taken again from `current`
    // (another tab, a file read, a save-as): the panel reloads its editor
    property int revision: 0
    // last session's open files, kept in XDG state so the editor reopens them
    readonly property string sessionFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/shani/text-editor-session.json"
    property bool restoring: false
    // bookmarks from the last session, keyed by path, applied as each file loads
    // (opens are async, so they cannot be attached in onLoaded itself)
    property var pendingBookmarks: ({})

    // TextArea is not made for big files; past this the editor says so
    readonly property int maxBytes: 2 * 1024 * 1024

    function nameOf(path) { return path === "" ? Tr.t("Untitled") : String(path).split("/").pop(); }
    function indexOf(path) { return root.docs.findIndex(d => d.path !== "" && d.path === path); }
    function touch() {
        root.docs = root.docs.slice();
        if (!root.restoring) saveSession();
    }
    function syncHistory() {
        const d = root.current;
        root.undoCount = d && d.history ? d.history.length : 0;
        root.redoCount = d && d.future ? d.future.length : 0;
    }
    // line bookmarks are per document, stored with it (0-based line numbers)
    function bookmarks() { const d = root.current; return d && d.bookmarks ? d.bookmarks.slice() : []; }
    function toggleBookmark(line) {
        const d = root.current;
        if (!d) return;
        if (!d.bookmarks) d.bookmarks = [];
        const i = d.bookmarks.indexOf(line);
        if (i >= 0) d.bookmarks.splice(i, 1);
        else { d.bookmarks.push(line); d.bookmarks.sort((a, b) => a - b); }
        root.touch();
    }
    // take the restored bookmark list for a path (once), or an empty one
    function takeBookmarks(path) {
        const b = root.pendingBookmarks[path];
        if (Array.isArray(b)) {
            delete root.pendingBookmarks[path];
            return b.slice();
        }
        return [];
    }
    function nextBookmark(from, delta) {
        const list = root.bookmarks();
        if (list.length === 0) return from;
        if (delta > 0) return list.find(l => l > from) !== undefined ? list.find(l => l > from) : list[0];
        for (let i = list.length - 1; i >= 0; i--) if (list[i] < from) return list[i];
        return list[list.length - 1];
    }

    function saveSession() {
        if (root.restoring || sessionView.path === "") return;
        const paths = [], bookmarks = {};
        root.docs.forEach(d => {
            if (d.path === "") return;
            paths.push(d.path);
            if (d.bookmarks && d.bookmarks.length) bookmarks[d.path] = d.bookmarks.slice();
        });
        sessionView.setText(JSON.stringify({ paths: paths, active: root.active, bookmarks: bookmarks }));
    }
    function restoreSession() {
        root.restoring = true;
        if (sessionView.path === root.sessionFile) sessionView.reload();
        else sessionView.path = root.sessionFile;
    }
    FileView {
        id: sessionView
        path: ""
        printErrors: false
        onLoaded: {
            let data = {};
            try { data = JSON.parse(text()); } catch (e) { data = {}; }
            const b = data.bookmarks;
            root.pendingBookmarks = b && typeof b === "object" && !Array.isArray(b) ? b : {};
            const paths = Array.isArray(data.paths) ? data.paths : [];
            paths.forEach(p => root.open(p));
            root.restoring = false;
        }
        onLoadFailed: root.restoring = false
    }

    function show(i) {
        if (i < 0 || i >= root.docs.length)
            return;
        root.active = i;
        root.syncHistory();
        root.revision++;
        saveSession();
    }

    function newDoc() {
        root.docs = root.docs.concat([{ path: "", name: nameOf(""), text: "", eol: "\n", modified: false, readOnly: false }]);
        show(root.docs.length - 1);
    }

    // "FILE", "file:///FILE" or "+LINE FILE" (the way a terminal's editor is asked)
    function open(arg) {
        let path = String(arg || "").trim();
        let line = 0;
        const m = path.match(/^\+(\d+)\s+(.+)$/);
        if (m) {
            line = parseInt(m[1]);
            path = m[2];
        }
        if (path.startsWith("file://"))
            path = decodeURIComponent(path.substring(7));
        if (path === "") {
            if (root.docs.length === 0)
                newDoc();
            return;
        }
        if (!path.startsWith("/"))
            path = (Quickshell.env("HOME") || "") + "/" + path;
        root.error = "";
        root.goToLine = line;
        const at = indexOf(path);
        if (at >= 0) {
            show(at);
            return;
        }
        probe.want = path;
        probe.command = ["sh", "-c", 'p=$(readlink -f -- "$1" 2>/dev/null) || p=$1; [ -d "$p" ] && { echo dir; exit; }; [ -e "$p" ] || { echo new; exit; }; [ -r "$p" ] || { echo unreadable; exit; }; s=$(stat -c %s -- "$p"); [ -w "$p" ] && w=rw || w=ro; if [ "$s" -gt 0 ] && ! grep -qI "" -- "$p"; then echo binary; else echo "file $s $w"; fi', "sh", path];
        probe.running = true;
    }

    // what the path is before it is read: a folder, a picture and a file too
    // big to edit are told apart from a text file, and say so
    Process {
        id: probe
        property string want: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim().split(" ");
                const path = probe.want;
                if (a[0] === "new") {
                    // a name that is not there yet: an empty document that Save creates
                    root.docs = root.docs.concat([{ path: path, name: root.nameOf(path), text: "", eol: "\n", modified: false, readOnly: false, bookmarks: root.takeBookmarks(path) }]);
                    root.show(root.docs.length - 1);
                } else if (a[0] === "file" && parseInt(a[1]) > root.maxBytes)
                    root.fail(Tr.t("Too big to edit here") + ": " + root.nameOf(path));
                else if (a[0] === "file") {
                    reader.readOnly = a[2] === "ro";
                    if (reader.path === path)
                        reader.reload();
                    else
                        reader.path = path;
                } else
                    root.fail((a[0] === "dir" ? Tr.t("That is a folder") : a[0] === "binary" ? Tr.t("Not a text file") : Tr.t("Cannot be read")) + ": " + root.nameOf(path));
            }
        }
    }
    function fail(why) {
        root.error = why;
        if (root.docs.length === 0)
            newDoc();
    }

    FileView {
        id: reader
        property bool readOnly: false
        path: ""
        printErrors: false
        onLoaded: {
            const p = String(path).replace(/^file:\/\//, "");
            if (p === "" || root.indexOf(p) >= 0)
                return;
            const raw = text();
            const eol = raw.indexOf("\r\n") >= 0 ? "\r\n" : "\n";
            // an empty "Untitled" nobody typed in gives its place to the file
            const keep = root.docs.filter(d => !(d.path === "" && d.text === "" && !d.modified));
            root.docs = keep.concat([{ path: p, name: root.nameOf(p), text: raw.replace(/\r\n/g, "\n"), eol: eol, modified: false, readOnly: readOnly, bookmarks: root.takeBookmarks(p) }]);
            root.show(root.docs.length - 1);
        }
        onLoadFailed: root.fail(Tr.t("Cannot be read") + ": " + root.nameOf(String(path)))
    }

    // the editor's text, as it is typed
    function setText(text) {
        const d = root.current;
        if (!d || d.text === text)
            return;
        if (!d.history) d.history = [];
        if (!d.future) d.future = [];
        d.history.push(d.text);
        if (d.history.length > 300)
            d.history.shift();
        d.future.length = 0;
        d.text = text;
        if (!d.modified) {
            d.modified = true;
            touch();
        }
        root.syncHistory();
    }

    // The panel calls these and writes the returned text into the editor while
    // its own change handler is suppressed, so undo doesn't push a new entry.
    function undo() {
        const d = root.current;
        if (!d || !d.history || d.history.length === 0)
            return null;
        if (!d.future) d.future = [];
        d.future.push(d.text);
        d.text = d.history.pop();
        if (!d.modified) { d.modified = true; touch(); }
        root.syncHistory();
        return d.text;
    }
    function redo() {
        const d = root.current;
        if (!d || !d.future || d.future.length === 0)
            return null;
        if (!d.history) d.history = [];
        d.history.push(d.text);
        d.text = d.future.pop();
        if (!d.modified) { d.modified = true; touch(); }
        root.syncHistory();
        return d.text;
    }

    // false: there is no name yet - the panel asks for one, then saveAs()
    function save() {
        const d = root.current;
        if (!d || root.saving)
            return true;
        if (d.path === "")
            return false;
        root.error = "";
        root.saving = true;
        writer.target = d.path;
        writer.doc = d;
        writer.path = d.path + ".shani-save";
        writer.setText(d.eol === "\r\n" ? d.text.replace(/\n/g, "\r\n") : d.text);
        return true;
    }
    function saveAs(path) {
        const d = root.current;
        if (!d || !path)
            return;
        d.path = path;
        d.name = nameOf(path);
        d.readOnly = false;
        touch();
        save();
    }

    FileView {
        id: writer
        property string target: ""
        property var doc: null
        path: ""
        printErrors: false
        onSaved: {
            place.command = ["sh", "-c", 't=$(readlink -f -- "$2" 2>/dev/null) || t=$2; [ -e "$t" ] && chmod --reference="$t" -- "$1" 2>/dev/null; mv -f -- "$1" "$t"', "sh", String(path).replace(/^file:\/\//, ""), target];
            place.running = true;
        }
        onSaveFailed: root.saveDone(false)
    }
    Process {
        id: place
        onExited: code => root.saveDone(code === 0)
    }
    function saveDone(ok) {
        root.saving = false;
        const d = writer.doc;
        writer.doc = null;
        if (!ok) {
            root.error = Tr.t("Could not save") + ": " + (d ? d.name : "");
            Quickshell.execDetached(["rm", "-f", "--", writer.target + ".shani-save"]);
            return;
        }
        if (d) {
            d.modified = false;
            root.lastSaved = d.path;
            touch();
        }
    }

    // closing a document that has changes is the panel's to confirm
    function close(i) {
        if (i < 0 || i >= root.docs.length)
            return;
        const list = root.docs.slice();
        list.splice(i, 1);
        root.docs = list;
        if (list.length === 0)
            newDoc();
        else
            show(Math.min(root.active > i ? root.active - 1 : root.active, list.length - 1));
        saveSession();
    }
    Process {
        id: sessionDir
        command: ["mkdir", "-p", root.sessionFile.substring(0, root.sessionFile.lastIndexOf("/"))]
        onExited: root.restoreSession()
    }
    Component.onCompleted: sessionDir.running = true
}
