pragma Singleton
// Quick notes: a folder of Markdown notes, ~/Documents/Notes/ — one
// .md file per note, saved as you type, readable by any editor and by
// Chronoa (Chronoa opens the file with openEditor; it can also just
// read the folder, since every note is plain Markdown on disk).
//
// Notebooks (Gnote parity): a notebook is a subfolder of ~/Documents/Notes/
// — notes inside it live as <notebook>/<note>.md, top-level notes stay as
// <note>.md. Create and rename a notebook in the sidebar; the legacy
// single file ~/Documents/Notes/quick.md is still one of the notes and
// stays where it is. Nothing is renamed away from under the person.
//
// Export + print (Gnote parity): the current note exports to a standalone
// .html (same folder, same base name, title in <title>/<h1>, body in <pre>)
// and prints via `lp` (CUPS). Sync is a TODO — clearly marked: there is
// no sync backend here and none is faked.
//
// [[Wiki links]] between notes: the editor shows the current note's
// links as chips under it; clicking one jumps to that note (creating
// it, empty, when it does not exist yet — the way a wiki does).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string dir: (Quickshell.env("XDG_DOCUMENTS_DIR") || Quickshell.env("HOME") + "/Documents") + "/Notes"
    // kept for the readers that only know the old shape (the desktop
    // widget, `state`): the note that is open now
    readonly property string path: root.current !== ""
        ? (root.currentNotebook !== "" ? root.dir + "/" + root.currentNotebook + "/" + root.current + ".md" : root.dir + "/" + root.current + ".md")
        : root.dir + "/quick.md"
    property var notes: []          // [{ name, path, notebook, id }] sorted by notebook/name
    property var notebooks: []      // notebook names (subfolders of dir), sorted; "" is the root, not listed
    property string current: ""     // the open note, without ".md"
    property string currentNotebook: ""  // the open note's notebook ("" = top level)
    property string text: ""        // its content — what the widget shows
    property bool loaded: false
    property bool exists: false     // there is at least one note on disk

    // ---- checklists / attachments / locked notes -----------------------------
    property string lastAttached: ""   // last file copied into assets/, for `state`
    property var unlockedIds: []       // ids of .locked.md notes unlocked this session
    property bool locked: false        // the open note is a .locked.md
    property bool unlocked: false      // its passphrase was accepted this session
    property string lockError: ""      // why the last lock/unlock failed

    // ---- export / print / sync (Gnote parity) ------------------------------
    property string lastExported: ""   // last .html written by exportHtml(), for `state`
    property string lastPrinted: ""    // last path sent to `lp` by printNote(), for `state`
    property string syncState: "TODO: notes sync is not implemented"  // no sync backend; never faked
    readonly property bool syncTodo: true

    // ---- listing ------------------------------------------------------------
    Process {
        id: list
        command: ["sh", "-c", 'd="$1"; mkdir -p "$d"; { for f in "$d"/*.md; do [ -e "$f" ] && basename "${f%.md}"; done; for sub in "$d"/*/; do [ -d "$sub" ] || continue; nb=$(basename "$sub"); for f in "$sub"*.md; do [ -e "$f" ] && printf "%s/%s\\n" "$nb" "$(basename "${f%.md}")"; done; done; } | sort', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(s => s !== "");
                const all = lines.map(line => {
                    const slash = line.indexOf("/");
                    const nb = slash >= 0 ? line.slice(0, slash) : "";
                    const name = slash >= 0 ? line.slice(slash + 1) : line;
                    return { name: name, path: nb === "" ? root.dir + "/" + name + ".md" : root.dir + "/" + nb + "/" + name + ".md", notebook: nb, id: nb === "" ? name : nb + "/" + name };
                });
                root.notes = all;
                root.exists = all.length > 0;
                if (root.current === "" && all.length > 0) {
                    const first = all.filter(x => x.notebook === "" && x.name === "quick")[0] || all[0];
                    root.open(first.name, first.notebook);
                }
                root.loaded = true;
            }
        }
    }
    Process {
        id: nbList
        command: ["sh", "-c", 'd="$1"; mkdir -p "$d"; for sub in "$d"/*/; do [ -d "$sub" ] && basename "$sub"; done | sort', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.notebooks = text.trim().split("\n").filter(s => s !== "");
            }
        }
    }
    function refresh() {
        list.running = true;
        nbList.running = true;
    }
    Component.onCompleted: refresh()

    // ---- paths --------------------------------------------------------------
    function validNotebook(name) {
        return valid(name);
    }
    function notePath(name, notebook) {
        const nb = validNotebook(notebook);
        const n = valid(name);
        return nb === "" ? root.dir + "/" + n + ".md" : root.dir + "/" + nb + "/" + n + ".md";
    }
    function noteId(name, notebook) {
        const nb = validNotebook(notebook);
        const n = valid(name);
        return nb === "" ? n : nb + "/" + n;
    }

    // ---- opening / saving ----------------------------------------------------
    FileView {
        id: file
        path: root.path
        printErrors: false
        onLoaded: {
            root.loaded = true;
            // a locked note stays blank until its passphrase is accepted,
            // even though FileView has already read the file
            if (isLocked(root.current) && !isUnlocked(noteId(root.current, root.currentNotebook)))
                return;
            // an outside edit (Chronoa, a text editor) is shown; when it
            // is empty and the open note is new, that stays empty too
            root.text = text();
        }
        onLoadFailed: root.loaded = true
    }
    FileView {
        id: exportView
        path: ""
        printErrors: false
    }
    function open(name, notebook) {
        if (!name)
            return;
        let raw = String(name);
        let nb = notebook;
        const slash = raw.indexOf("/");
        if (nb === undefined && slash >= 0) {
            nb = raw.slice(0, slash);
            raw = raw.slice(slash + 1);
        }
        const n = valid(raw);
        if (n === "")
            return;
        if (nb === undefined || nb === null) {
            const found = notes.filter(x => x.name === n)[0];
            nb = found ? found.notebook : root.currentNotebook;
        }
        nb = validNotebook(nb);
        if (n === root.current && nb === root.currentNotebook)
            return;
        save.stop();   // do not write the old note's text into the new path
        root.current = n;
        root.currentNotebook = nb;
        root.locked = isLocked(n);
        root.unlocked = isUnlocked(noteId(n, nb));
        root.lockError = "";
        root.text = "";
        file.path = root.path;   // the path follows `current` (+ notebook)
        file.reload();
        // a .locked.md with no sidecar protects nothing: treat it as open
        if (root.locked && !root.unlocked)
            runLock("state", lockPath(n, nb), "", noteId(n, nb));
    }
    function set(t) {
        if (isLocked(root.current) && !isUnlocked(noteId(root.current, root.currentNotebook)))
            return;   // never overwrite a note whose body we cannot read
        text = t;
        if (root.current !== "")
            save.restart();
    }
    Timer {
        id: save
        interval: 600
        onTriggered: {
            if (isLocked(root.current) && !isUnlocked(noteId(root.current, root.currentNotebook)))
                return;
            const dirPath = root.currentNotebook === "" ? root.dir : root.dir + "/" + root.currentNotebook;
            Quickshell.execDetached(["mkdir", "-p", dirPath]);
            file.setText(root.text);
        }
    }

    // ---- create / rename / delete --------------------------------------------
    function valid(name) {
        const n = String(name || "").trim().replace(/\.md$/, "").replace(/[\/\\:*?"<>|]/g, " ").replace(/\s+/g, " ").trim();
        return n;
    }
    function create(name, notebook) {
        const n = valid(name);
        if (n === "")
            return;
        let nb = notebook;
        if (nb === undefined || nb === null)
            nb = root.currentNotebook;
        nb = validNotebook(nb);
        if (notes.some(x => x.name === n && x.notebook === nb))
            return;
        const dirPath = nb === "" ? root.dir : root.dir + "/" + nb;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && : > "$1/$2.md"', "sh", dirPath, n]);
        root.open(n, nb);
        refresh();
    }
    function rename(oldName, newName, notebook) {
        const n = valid(newName);
        if (!oldName || n === "")
            return;
        let old = String(oldName);
        let nb = notebook;
        if (nb === undefined) {
            const slash = old.indexOf("/");
            if (slash >= 0) {
                nb = old.slice(0, slash);
                old = old.slice(slash + 1);
            } else {
                const found = notes.filter(x => x.name === valid(old))[0];
                nb = found ? found.notebook : root.currentNotebook;
            }
        }
        nb = validNotebook(nb);
        old = valid(old);
        if (n === old)
            return;
        if (notes.some(x => x.name === n && x.notebook === nb))
            return;
        const oldPath = notePath(old, nb);
        const newPath = notePath(n, nb);
        save.stop();
        Quickshell.execDetached(["sh", "-c", 'mv -- "$1" "$2"', "sh", oldPath, newPath]);
        if (root.current === old && root.currentNotebook === nb) {
            root.current = n;
            file.path = root.path;
            file.reload();
        }
        refresh();
    }
    function remove(name, notebook) {
        if (!name)
            return;
        let raw = String(name);
        let nb = notebook;
        if (nb === undefined) {
            const slash = raw.indexOf("/");
            if (slash >= 0) {
                nb = raw.slice(0, slash);
                raw = raw.slice(slash + 1);
            } else {
                const found = notes.filter(x => x.name === valid(raw))[0];
                nb = found ? found.notebook : root.currentNotebook;
            }
        }
        nb = validNotebook(nb);
        const n = valid(raw);
        if (n === "")
            return;
        Quickshell.execDetached(["sh", "-c", 'rm -f -- "$1"', "sh", notePath(n, nb)]);
        if (root.current === n && root.currentNotebook === nb) {
            root.current = "";
            root.currentNotebook = "";
            const rest = notes.filter(x => !(x.name === n && x.notebook === nb));
            if (rest.length > 0)
                root.open(rest[0].name, rest[0].notebook);
            else
                root.loaded = true;
        }
        refresh();
    }

    // ---- notebooks (Gnote parity: folders = notebooks) ------------------------
    function createNotebook(name) {
        const n = validNotebook(name);
        if (n === "" || notebooks.indexOf(n) >= 0)
            return;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1/$2"', "sh", root.dir, n]);
        refresh();
    }
    function renameNotebook(oldName, newName) {
        const o = validNotebook(oldName);
        const n = validNotebook(newName);
        if (o === "" || n === "" || o === n || notebooks.indexOf(n) >= 0)
            return;
        save.stop();
        Quickshell.execDetached(["sh", "-c", 'mv -- "$1/$2" "$1/$3"', "sh", root.dir, o, n]);
        if (root.currentNotebook === o) {
            root.currentNotebook = n;
            file.path = root.path;
            file.reload();
        }
        refresh();
    }
    function deleteNotebook(name) {
        const n = validNotebook(name);
        if (n === "")
            return;
        Quickshell.execDetached(["sh", "-c", 'rm -rf -- "$1/$2"', "sh", root.dir, n]);
        if (root.currentNotebook === n) {
            root.current = "";
            root.currentNotebook = "";
            const rest = notes.filter(x => x.notebook !== n);
            if (rest.length > 0)
                root.open(rest[0].name, rest[0].notebook);
        }
        refresh();
    }

    // ---- export / print -------------------------------------------------------
    function escapeHtml(s) {
        return String(s === undefined || s === null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }
    // standalone .html: title in <title> and <h1>, body in <pre>
    function htmlDocument(title, body) {
        const t = escapeHtml(title || root.current || "note");
        const b = escapeHtml(body === undefined ? root.text : body);
        return "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>" + t + "</title>\n</head>\n<body>\n<h1>" + t + "</h1>\n<pre>" + b + "</pre>\n</body>\n</html>\n";
    }
    function exportPath() {
        if (root.current === "")
            return "";
        return root.path.replace(/\.md$/, ".html");
    }
    // current note -> .html file with title/body (default: next to the .md)
    function exportHtml(dest) {
        if (root.current === "")
            return "";
        const target = dest ? String(dest) : root.exportPath();
        if (target === "")
            return "";
        exportView.path = target;
        exportView.setText(htmlDocument(root.current, root.text));
        root.lastExported = target;
        return target;
    }
    // print the current note via `lp` (the same CUPS backend Printing uses)
    function printNote() {
        if (root.current === "")
            return "";
        root.lastPrinted = root.path;
        Quickshell.execDetached(["lp", "--", root.path]);
        return root.path;
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
    // go to a linked note, creating it empty in the current notebook
    function jumpTo(name) {
        const n = valid(name);
        if (n === "") return;
        const found = notes.filter(x => x.name === n)[0];
        if (found)
            open(found.name, found.notebook);
        else
            create(n, root.currentNotebook || "");
    }
    // notes whose name, notebook or open-note text matches q
    function search(q) {
        const needle = String(q || "").trim().toLowerCase();
        if (needle === "")
            return notes;
        return notes.filter(n => n.name.toLowerCase().indexOf(needle) >= 0
            || (n.notebook || "").toLowerCase().indexOf(needle) >= 0
            || (root.current === n.name && root.currentNotebook === (n.notebook || "") && root.text.toLowerCase().indexOf(needle) >= 0));
    }
    // the other notes' bodies, searched on disk (the open one is `search`
    // already): contentHits holds ids ("note" or "notebook/note")
    property var contentHits: []
    Process {
        id: grepBodies
        property string query: ""
        command: ["sh", "-c", 'd="$1"; q="$2"; [ "$q" = "" ] && exit 0; grep -liF -- "$q" "$d"/*.md "$d"/*/*.md 2>/dev/null | while read -r f; do rel=${f#"$d"/}; printf "%s\\n" "${rel%.md}"; done', "sh", root.dir, query]
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
    function preview(name, notebook) {
        let raw = String(name || "");
        let nb = notebook;
        const slash = raw.indexOf("/");
        if (nb === undefined && slash >= 0) {
            nb = raw.slice(0, slash);
            raw = raw.slice(slash + 1);
        }
        if (nb !== undefined)
            nb = validNotebook(nb);
        if (raw !== root.current)
            return "";
        if (nb !== undefined && nb !== root.currentNotebook)
            return "";
        return root.text.split("\n").find(l => l.trim() !== "") || "";
    }

    // ---- checklists -----------------------------------------------------------
    // Toggle the checkbox on a 0-based line of the current note. Returns false
    // when that line is not a Markdown task, so a click elsewhere does nothing.
    function toggleChecklistItem(lineIndex) {
        const lines = String(root.text).split("\n");
        const i = Number(lineIndex);
        if (!(i >= 0) || i >= lines.length)
            return false;
        const m = /^(\s*[-*+]\s+\[)([ xX])(\].*)$/.exec(lines[i]);
        if (!m)
            return false;
        lines[i] = m[1] + (m[2] === " " ? "x" : " ") + m[3];
        set(lines.join("\n"));
        return true;
    }
    // Insert a fresh "- [ ] " at a character position and return the new cursor
    // position: the service owns the text, the surface owns the cursor.
    function insertChecklistItem(pos) {
        const t = String(root.text);
        const at = Math.max(0, Math.min(pos === undefined ? t.length : Number(pos), t.length));
        const lead = at > 0 && t[at - 1] !== "\n" ? "\n" : "";
        set(t.slice(0, at) + lead + "- [ ] " + t.slice(at));
        return at + lead.length + 6;
    }

    // ---- attachments ----------------------------------------------------------
    // Pick a file, copy it into <notesdir>/assets/ (never overwriting one that
    // is already there) and link it from the end of the current note.
    function attachFile() {
        if (root.current === "")
            return;
        FilePicker.open({ mode: "open", title: Tr.t("A file to attach to this note"),
                          onPicked: paths => {
                              if (!paths.length)
                                  return;
                              const src = paths[0];
                              const name = src.slice(src.lastIndexOf("/") + 1);
                              if (!name)
                                  return;
                              const folder = root.dir + "/assets";
                              attach.name = name;
                              attach.command = ["sh", "-c", 'mkdir -p "$1" && cp -n -- "$2" "$3"', "sh", folder, src, folder + "/" + name];
                              attach.running = true;
                          } });
    }
    Process {
        id: attach
        property string name: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0)
                return;
            root.lastAttached = name;
            // escape the markdown link's delimiters; spaces in a URL are %20
            const textName = name.replace(/([\[\]\\])/g, "\\$1");
            const urlName = name.replace(/ /g, "%20").replace(/([()])/g, "\\$1");
            set(String(root.text).replace(/\s*$/, "") + "\n[" + textName + "](assets/" + urlName + ")");
        }
    }

    // ---- locked notes ---------------------------------------------------------
    // <name>.locked.md is private in the UI: the sidecar <name>.locked.lock
    // holds the SHA-256 of its passphrase on the first line. shortcut: this
    // hides the body in the shell, it does not encrypt the file on disk;
    // upgrade to gpg symmetric encryption if secrecy at rest is needed.
    function isLocked(name) { return /\.locked$/.test(String(name || "")); }
    function isUnlocked(id) { return unlockedIds.indexOf(id) >= 0; }
    function lockPath(name, notebook) {
        return notePath(name, notebook).replace(/\.md$/, ".lock");
    }
    function markUnlocked(id) {
        if (!isUnlocked(id))
            unlockedIds = unlockedIds.concat([id]);
        root.locked = isLocked(root.current);
        root.unlocked = isUnlocked(noteId(root.current, root.currentNotebook));
    }
    // one small shell helper: set the hash, check it, or ask if a lock exists.
    // The passphrase travels as argv, never interpolated into the command.
    function runLock(mode, sidecar, passphrase, id) {
        lockProc.mode = mode;
        lockProc.id = id;
        lockProc.command = ["sh", "-c",
            'case "$1" in set) printf %s "$3" | sha256sum | cut -d" " -f1 > "$2" ;; check) got=$(printf %s "$3" | sha256sum | cut -d" " -f1); want=$(head -n1 "$2" 2>/dev/null); [ -n "$want" ] && [ "$got" = "$want" ] ;; state) [ -s "$2" ] ;; esac',
            "sh", mode, sidecar, passphrase];
        lockProc.running = true;
    }
    Process {
        id: lockProc
        property string mode: ""
        property string id: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (mode === "state") {
                if (code !== 0) {   // no sidecar: nothing is actually hidden
                    markUnlocked(id);
                    if (id === noteId(root.current, root.currentNotebook))
                        file.reload();
                }
                return;
            }
            if (mode === "set") {
                if (code !== 0) {
                    root.lockError = Tr.t("Could not save the lock");
                    return;
                }
                markUnlocked(id);
                root.lockError = "";
                refresh();
                return;
            }
            if (code === 0) {
                markUnlocked(id);
                root.lockError = "";
                if (id === noteId(root.current, root.currentNotebook))
                    file.reload();
            } else {
                root.lockError = Tr.t("Wrong passphrase");
            }
        }
    }
    // Lock the open note: give it the .locked.md name, then store the hash.
    function lockNote(passphrase) {
        const pass = String(passphrase || "");
        if (root.current === "" || pass === "")
            return;
        let n = root.current;
        let nb = root.currentNotebook;
        if (!isLocked(n)) {
            rename(n, n + ".locked", nb);
            if (!isLocked(root.current))
                return;   // a note with that name already exists
            n = root.current;
            nb = root.currentNotebook;
        }
        root.locked = true;
        root.unlocked = false;
        root.lockError = "";
        runLock("set", lockPath(n, nb), pass, noteId(n, nb));
    }
    function unlockNote(passphrase) {
        const pass = String(passphrase || "");
        if (root.current === "" || !isLocked(root.current) || pass === "")
            return;
        root.lockError = "";
        runLock("check", lockPath(root.current, root.currentNotebook), pass, noteId(root.current, root.currentNotebook));
    }
}
