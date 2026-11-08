pragma Singleton
// Quick notes: a folder of Markdown notes, ~/Documents/Notes/ — one
// .md file per note, saved as you type, readable by any editor and by
// Chronoa (Chronoa opens the file with openEditor; it can also just
// read the folder, since every note is plain Markdown on disk).
//
// The legacy single file ~/Documents/Notes/quick.md is still one of the
// notes: on first run, when the folder holds nothing but that file (or
// nothing at all) it stays as it is, shown as a note named "quick".
// Nothing is renamed away from under the person.
//
// [[Wiki links]] between notes: the editor shows the current note's
// links as chips under it; clicking one jumps to that note (creating
// it, empty, when it does not exist yet — the way a wiki does).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string dir: (Quickshell.env("XDG_DOCUMENTS_DIR") || Quickshell.env("HOME") + "/Documents") + "/Notes"
    // kept for the readers that only know the old shape (the desktop
    // widget, `state`): the note that is open now
    readonly property string path: root.current !== "" ? root.dir + "/" + root.current + ".md"
        : root.dir + "/quick.md"
    property var notes: []          // [{ name, path }] sorted by name
    property string current: ""     // the open note, without ".md"
    property string text: ""        // its content — what the widget shows
    property bool loaded: false
    property bool exists: false     // there is at least one note on disk

    // ---- listing ------------------------------------------------------------
    Process {
        id: list
        command: ["sh", "-c", 'd="$1"; mkdir -p "$d"; for f in "$d"/*.md; do [ -e "$f" ] && basename "${f%.md}"; done | sort', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.trim().split("\n").filter(s => s !== "");
                root.notes = names.map(n => ({ name: n, path: root.dir + "/" + n + ".md" }));
                root.exists = names.length > 0;
                if (root.current === "" && names.length > 0) {
                    const first = names.indexOf("quick") >= 0 ? "quick" : names[0];
                    root.open(first);
                }
                root.loaded = true;
            }
        }
    }
    function refresh() { list.running = true; }
    Component.onCompleted: refresh()

    // ---- opening / saving ----------------------------------------------------
    FileView {
        id: file
        path: root.path
        printErrors: false
        onLoaded: {
            // an outside edit (Chronoa, a text editor) is shown; when it
            // is empty and the open note is new, that stays empty too
            root.text = text();
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
    function open(name) {
        if (!name || name === root.current)
            return;
        save.stop();   // do not write the old note's text into the new path
        root.current = name;
        root.text = "";
        file.path = root.path;   // the path follows `current`
        file.reload();
    }
    function set(t) {
        text = t;
        if (root.current !== "")
            save.restart();
    }
    Timer {
        id: save
        interval: 600
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", root.dir]);
            file.setText(root.text);
        }
    }

    // ---- create / rename / delete --------------------------------------------
    function valid(name) {
        const n = String(name || "").trim().replace(/\.md$/, "").replace(/[\/\\:*?"<>|]/g, " ").replace(/\s+/g, " ").trim();
        return n;
    }
    function create(name) {
        const n = valid(name);
        if (n === "" || notes.some(x => x.name === n)) return;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && : > "$1/$2.md"', "sh", root.dir, n]);
        root.open(n);
        refresh();
    }
    function rename(oldName, newName) {
        const n = valid(newName);
        if (!oldName || n === "" || n === oldName || notes.some(x => x.name === n)) return;
        const oldPath = root.dir + "/" + oldName + ".md";
        const newPath = root.dir + "/" + n + ".md";
        save.stop();
        Quickshell.execDetached(["sh", "-c", 'mv -- "$1" "$2"', "sh", oldPath, newPath]);
        if (root.current === oldName) {
            root.current = n;
            file.path = root.path;
            file.reload();
        }
        refresh();
    }
    function remove(name) {
        if (!name) return;
        Quickshell.execDetached(["sh", "-c", 'rm -f -- "$1"', "sh", root.dir + "/" + name + ".md"]);
        if (root.current === name) {
            root.current = "";
            const rest = notes.filter(x => x.name !== name).map(x => x.name);
            if (rest.length > 0)
                root.open(rest[0]);
            else
                root.loaded = true;
        }
        refresh();
    }

    // ---- [[wiki links]] -------------------------------------------------------
    // names inside [[ ]] in the current text, in order of first appearance
    function links() {
        const out = [];
        const re = /\[\[([^\[\]]+)\]\]/g;
        let m;
        while ((m = re.exec(text || "")) !== null) {
            const n = m[1].trim();
            if (n !== "" && out.indexOf(n) < 0)
                out.push(n);
        }
        return out;
    }
    // go to a linked note, creating it empty when there is none yet
    function jumpTo(name) {
        const n = valid(name);
        if (n === "") return;
        if (notes.some(x => x.name === n))
            open(n);
        else
            create(n);
    }
    // notes whose name or text matches q (the sidebar search)
    function search(q) {
        const needle = String(q || "").trim().toLowerCase();
        if (needle === "")
            return notes;
        return notes.filter(n => n.name.toLowerCase().indexOf(needle) >= 0
            || (root.current === n.name ? root.text.toLowerCase().indexOf(needle) >= 0 : false));
    }
    // the other notes' bodies, searched on disk (the open one is `search`
    // already): contentHits names them, in `notes` order
    property var contentHits: []
    Process {
        id: grepBodies
        property string query: ""
        command: ["sh", "-c", 'd="$1"; q="$2"; [ "$q" = "" ] && exit 0; grep -liF -- "$q" "$d"/*.md 2>/dev/null | while read -r f; do basename "${f%.md}"; done', "sh", root.dir, query]
        stdout: StdioCollector {
            onStreamFinished: root.contentHits = text.trim().split("\n").filter(s => s !== "");
        }
    }
    function searchBodies(q) {
        grepBodies.query = String(q || "").trim();
        if (grepBodies.query !== "")
            grepBodies.running = true;
        else
            root.contentHits = [];
    }
    // every note's first non-empty line, for a preview in the list
    function preview(name) {
        return name === root.current ? root.text.split("\n").find(l => l.trim() !== "") || "" : "";
    }
}
