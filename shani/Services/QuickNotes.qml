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
    // trash, version history, sort and tags (the note is still a plain .md)
    readonly property string trashDir: root.dir + "/.trash"
    readonly property string historyDir: root.dir + "/.history"
    property var trashed: []
    property var historyList: []
    property string sortBy: Settings.data.notesSortBy || "updated"
    property var previews: ({})

    // ---- export / print / sync (Gnote parity) ------------------------------
    property string lastExported: ""   // last .html written by exportHtml(), for `state`
    property string lastPrinted: ""    // last path sent to `lp` by printNote(), for `state`
    property string syncState: Settings.data.notesSyncPath ? Tr.t("Not synced yet") : Tr.t("No sync folder chosen")  // local-first; sync to a chosen cloud mount
    readonly property string syncPath: Settings.data.notesSyncPath || ""
    Process {
        id: noteSync
        onExited: code => {
            root.syncState = code === 0 ? Tr.t("Synced %1", Qt.formatTime(new Date(), "HH:mm"))
                                        : Tr.t("Sync failed — check the folder");
        }
    }
    function syncNotes() {
        if (!root.syncPath) return;
        Quickshell.execDetached(["mkdir", "-p", root.syncPath]);
        noteSync.command = ["sh", "-c", 'rsync -au "$1/" "$2/Notes/" 2>/dev/null', "sh", root.dir, root.syncPath];
        noteSync.running = true;
    }
    Timer { id: syncTimer; interval: 4000; onTriggered: root.syncNotes() }
    readonly property bool syncTodo: true

    // ---- listing ------------------------------------------------------------
    Process {
        id: list
        command: ["sh", "-c", 'd="$1"; mkdir -p "$d"; { for f in "$d"/*.md; do [ -e "$f" ] && printf "%s\\t%s\\n" "$(stat -c %Y "$f")" "$(basename "${f%.md}")"; done; for sub in "$d"/*/; do [ -d "$sub" ] || continue; nb=$(basename "$sub"); for f in "$sub"*.md; do [ -e "$f" ] && printf "%s\\t%s/%s\\n" "$(stat -c %Y "$f")" "$nb" "$(basename "${f%.md}")"; done; done; } | sort -rn', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(s => s !== "");
                const all = lines.map(line => {
                    const bits = line.split("\t");
                    const id = bits.length > 1 ? bits[1] : line;
                    const slash = id.indexOf("/");
                    const nb = slash >= 0 ? id.slice(0, slash) : "";
                    const name = slash >= 0 ? id.slice(slash + 1) : id;
                    return { name: name, path: nb === "" ? root.dir + "/" + name + ".md" : root.dir + "/" + nb + "/" + name + ".md", notebook: nb, id: id, mtime: Number(bits[0]) || 0 };
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
        trashList.running = true;
        previewProc.running = true;
    }
    Process {
        id: previewProc
        command: ["sh", "-c", 'd="$1"; for f in "$d"/*.md "$d"/*/*.md; do [ -e "$f" ] || continue; p=$(grep -m1 -v "^[[:space:]]*$" -- "$f" 2>/dev/null | head -c 120); rel=${f#"$d"/}; printf "%s\\t%s\\n" "${rel%.md}" "$p"; done', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                text.trim().split("\n").forEach(line => {
                    const i = line.indexOf("\t");
                    if (i > 0) map[line.slice(0, i)] = line.slice(i + 1);
                });
                root.previews = map;
            }
        }
    }
    Component.onCompleted: { refresh(); cryptoProbe.running = true; if (root.syncPath) root.syncNotes() }

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
        root.pass = "";          // one unlocked note at a time
        if (isLocked(n)) {
            root.locked = true;
            root.unlocked = false;
            file.path = lockedPath(n, nb);   // ciphertext; never feed it to a text editor
            return;                          // wait for unlockNote() to fill root.text
        }
        file.path = root.path;   // the path follows `current` (+ notebook)
        file.reload();
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
            if (root.current === "")
                return;
            const lid = noteId(root.current, root.currentNotebook);
            if (isLocked(root.current)) {
                if (!isUnlocked(lid) || root.pass === "")
                    return;
                if (noteCrypto.running) noteCrypto.running = false;   // latest text wins
                noteCrypto.mode = "encrypt";
                noteCrypto.pendingPass = root.pass;
                noteCrypto.payload = JSON.stringify({ passphrase: root.pass, text: root.text });
                noteCrypto.command = ["python3", root.cryptoTool, "encrypt", lockedPath(root.current, root.currentNotebook)];
                noteCrypto.running = true;
                return;
            }
            const dirPath = root.currentNotebook === "" ? root.dir : root.dir + "/" + root.currentNotebook;
            Quickshell.execDetached(["mkdir", "-p", dirPath]);
            root.snapshot();   // keep the previous body before overwriting it
            file.setText(root.text);
            root.syncTimer.restart();   // local-first, then mirror to the cloud mount
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
    // Deleting a note moves its file to .trash instead of rm: a second tap
    // in the UI is still needed, but a deletion can now be put back.
    function remove(name, notebook) {
        if (!name) return;
        let raw = String(name);
        let nb = notebook;
        if (nb === undefined) {
            const slash = raw.indexOf("/");
            if (slash >= 0) { nb = raw.slice(0, slash); raw = raw.slice(slash + 1); }
            else {
                const found = notes.filter(x => x.name === valid(raw))[0];
                nb = found ? found.notebook : root.currentNotebook;
            }
        }
        nb = validNotebook(nb);
        const n = valid(raw);
        if (n === "") return;
        // shortcut: notebook/name is flattened with "__"; a name containing
        // "__" is ambiguous, use a notebook-free note name for those
        const key = (nb ? nb + "__" : "") + n;
        save.stop();
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && mv -f -- "$2" "$3"', "sh",
            root.trashDir, notePath(n, nb), root.trashDir + "/" + key + ".md"]);
        if (root.current === n && root.currentNotebook === nb) {
            root.current = "";
            root.currentNotebook = "";
            const rest = notes.filter(x => !(x.name === n && x.notebook === nb));
            if (rest.length > 0) root.open(rest[0].name, rest[0].notebook);
            else root.loaded = true;
        }
        refresh();
        trashList.running = true;
    }
    // put a trashed note back where it came from
    function restore(key) {
        const k = String(key || "");
        if (k === "") return;
        const i = k.indexOf("__");
        const nb = i >= 0 ? k.slice(0, i) : "";
        const n = i >= 0 ? k.slice(i + 2) : k;
        const folder = nb === "" ? root.dir : root.dir + "/" + nb;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && mv -f -- "$2" "$3"', "sh",
            folder, root.trashDir + "/" + k + ".md", notePath(n, nb)]);
        trashList.running = true;
        refresh();
    }
    function emptyTrash() {
        Quickshell.execDetached(["sh", "-c", 'rm -f -- "$1"/*.md', "sh", root.trashDir]);
        root.trashed = [];
    }
    Process {
        id: trashList
        command: ["sh", "-c", 'd="$1"; mkdir -p "$d"; for f in "$d"/*.md; do [ -e "$f" ] && basename "${f%.md}"; done | sort', "sh", root.trashDir]
        stdout: StdioCollector {
            onStreamFinished: root.trashed = text.trim().split("\n").filter(s => s !== "");
        }
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
        // a locked note's path is ciphertext: print the plaintext in memory
        root.lastPrinted = root.current;
        if (isLocked(root.current)) {
            if (!isUnlocked(noteId(root.current, root.currentNotebook)))
                return "";
            printProc.stdinEnabled = true;
            printProc.running = true;
            return root.current;
        }
        Quickshell.execDetached(["lp", "--", root.path]);
        return root.path;
    }
    Process {
        id: printProc
        command: ["lp", "-"]
        stdinEnabled: true
        onStarted: { write(root.text); stdinEnabled = false; }
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
    property var bodyResults: []
    Process {
        id: grepBodies
        property string query: ""
        command: ["sh", "-c", 'd="$1"; q="$2"; [ "$q" = "" ] && exit 0; grep -liF -- "$q" "$d"/*.md "$d"/*/*.md 2>/dev/null | while read -r f; do rel=${f#"$d"/}; printf "%s\\n" "${rel%.md}"; done', "sh", root.dir, query]
        stdout: StdioCollector {
            onStreamFinished: {
                const hits = text.trim().split("\n").filter(s => s !== "");
                root.contentHits = hits;
                // browseable results, not just results[0]
                root.bodyResults = hits.map(id => {
                    const slash = id.indexOf("/");
                    return { id: id, name: slash >= 0 ? id.slice(slash + 1) : id,
                             notebook: slash >= 0 ? id.slice(0, slash) : "" };
                });
            }
        }
    }
    function searchBodies(q) {
        // a query that changes leaves the last answer behind unless it is
        // dropped first: the launcher would show "found in content" for a word
        // nobody typed any more
        if (grepBodies.query !== String(q || "").trim()) {
            root.contentHits = [];
            root.bodyResults = [];
        }
        grepBodies.query = String(q || "").trim();
        if (grepBodies.query !== "")
            grepBodies.running = true;
        else {
            root.contentHits = [];
            root.bodyResults = [];
        }
        return root.bodyResults;
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
        const key = noteId(raw, nb === undefined ? root.currentNotebook : nb);
        if (raw === root.current && (nb === undefined || nb === root.currentNotebook))
            return root.text.split("\n").find(l => l.trim() !== "") || "";
        return root.previews[key] || "";
    }

    // ---- version history ------------------------------------------------------
    // one dated copy per autosave, capped at 20, so "Earlier versions" really
    // has something to show. Locked notes are skipped: their file is ciphertext.
    function snapshot() {
        if (root.current === "" || isLocked(root.current)) return;
        const src = root.path;
        const key = noteId(root.current, root.currentNotebook).replace("/", "__");
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss-zzz");
        const dest = root.historyDir + "/" + key + "-" + stamp + ".md";
        snapshotProc.command = ["sh", "-c",
            '[ -f "$1" ] || exit 0; mkdir -p "$2" && cp -p -- "$1" "$3"; ls -1t "$2"/"$4"-*.md 2>/dev/null | tail -n +21 | while read -r old; do rm -f -- "$old"; done',
            "sh", src, root.historyDir, dest, key];
        snapshotProc.running = true;
    }
    Process {
        id: snapshotProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }
    function history(id) {
        const key = String(id || root.current || "").replace("/", "__");
        histProc.command = ["sh", "-c",
            'd="$1/.history"; [ -d "$d" ] || exit 0; ls -1t "$d"/"$2"-*.md 2>/dev/null | head -20',
            "sh", root.dir, key];
        histProc.running = true;
    }
    Process {
        id: histProc
        stdout: StdioCollector {
            onStreamFinished: root.historyList = text.trim().split("\n").filter(s => s !== "");
        }
    }
    function restoreVersion(path) {
        if (!path) return;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && cp -f -- "$2" "$3"', "sh",
            root.dir + "/" + root.currentNotebook, path, root.path]);
        file.reload();
        refresh();
    }

    // ---- tags and due dates ---------------------------------------------------
    // #tags in the body, and @due(YYYY-MM-DD) on a Markdown task line
    function tags() {
        const out = [];
        const re = /#[A-Za-z0-9_-]+/g;
        let m;
        while ((m = re.exec(String(root.text || ""))) !== null)
            if (out.indexOf(m[0]) < 0) out.push(m[0]);
        return out.sort();
    }
    function notesWithTag(tag) {
        searchBodies(tag);
        return root.bodyResults;
    }
    function setDueDate(lineIndex, due) {
        const lines = String(root.text).split("\n");
        const i = Number(lineIndex);
        if (!(i >= 0) || i >= lines.length) return false;
        const m = /^(\s*[-*+]\s+\[[ xX]\][^\n]*)$/.exec(lines[i]);
        if (!m) return false;
        let line = m[1].replace(/\s*@due\([^)]*\)\s*$/, "");
        if (String(due || "").trim() !== "") line += " @due(" + String(due).trim() + ")";
        lines[i] = line;
        set(lines.join("\n"));
        return true;
    }
    function dueDates() {
        const out = [];
        String(root.text || "").split("\n").forEach((line, i) => {
            const task = /^\s*[-*+]\s+\[([ xX])\]/.exec(line);
            if (!task || task[1] !== " ") return;
            const d = /@due\(([^)]+)\)/.exec(line);
            if (d) out.push({ line: i, due: d[1].trim(),
                              text: line.replace(/@due\([^)]*\)/, "").trim() });
        });
        return out.sort((a, b) => String(a.due).localeCompare(String(b.due)));
    }

    // ---- sorting --------------------------------------------------------------
    function sortedNotes(list) {
        const arr = (list || root.notes).slice();
        if (root.sortBy === "title")
            return arr.sort((a, b) => String(a.name).localeCompare(String(b.name)));
        if (root.sortBy === "created")
            return arr.sort((a, b) => String(a.id).localeCompare(String(b.id)));
        return arr.sort((a, b) => b.mtime - a.mtime);   // updated: newest first
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

    // ---- locked notes: real symmetric encryption (gpg) ------------------------
    // The file on disk is <name>.locked.md.gpg (armored ciphertext). Plaintext
    // lives only in root.text (memory). bridge/note-crypto.py handles the gpg
    // call with the passphrase on a pipe fd, never in argv. No SHA-256 sidecar:
    // gpg's own failure is the passphrase check.
    function isLocked(name) { return /\.locked$/.test(String(name || "")); }
    function isUnlocked(id) { return unlockedIds.indexOf(id) >= 0; }
    function lockedPath(name, notebook) { return notePath(name, notebook) + ".gpg"; }
    function markUnlocked(id) {
        if (!isUnlocked(id))
            unlockedIds = unlockedIds.concat([id]);
        root.locked = isLocked(root.current);
        root.unlocked = isUnlocked(noteId(root.current, root.currentNotebook));
    }

    readonly property string cryptoTool: Quickshell.env("SHANI_NOTES_CRYPTO") || "/usr/lib/shani-shell/note-crypto.py"
    property bool cryptoAvailable: true
    property string pass: ""                  // passphrase of the unlocked note, memory only
    Process {
        id: cryptoProbe
        command: ["python3", root.cryptoTool, "probe"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.cryptoAvailable = (JSON.parse(text) || {}).gpg === true; }
                catch (e) { root.cryptoAvailable = false; }
            }
        }
    }
    Process {
        id: noteCrypto
        property string mode: ""
        property string pendingPass: ""
        property string newName: ""
        stdinEnabled: true
        onStarted: { write(payload); payload = ""; stdinEnabled = false; }
        property string payload: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                root.cryptoDone(r);
            }
        }
        stderr: StdioCollector {}
        onExited: code => { if (code !== 0 && text.trim() === "") root.lockError = Tr.t("Encryption failed (is gpg installed?)"); }
    }
    function cryptoDone(r) {
        if (r.error) { root.lockError = Tr.t(r.error); return; }
        if (noteCrypto.mode === "decrypt") {
            root.text = String(r.text || "");
            root.pass = noteCrypto.pendingPass;
            markUnlocked(noteId(root.current, root.currentNotebook));
            root.lockError = "";
        } else if (noteCrypto.mode === "lock") {
            root.current = noteCrypto.newName;
            root.pass = noteCrypto.pendingPass;
            root.text = "";
            root.lockError = "";
            file.path = lockedPath(root.current, root.currentNotebook);  // the ciphertext, never reloaded
            refresh();
        } else if (noteCrypto.mode === "encrypt") {
            root.lockError = "";   // autosave wrote the ciphertext
        }
    }
    function lockNote(passphrase) {
        const pass = String(passphrase || "");
        if (root.current === "" || pass === "" || !root.cryptoAvailable)
            return;
        if (!root.cryptoAvailable) {
            root.lockError = Tr.t("Locked notes need gpg, which is not installed");
            return;
        }
        const n = isLocked(root.current) ? root.current : root.current + ".locked";
        noteCrypto.mode = "lock";
        noteCrypto.pendingPass = pass;
        noteCrypto.newName = n;
        noteCrypto.payload = JSON.stringify({ passphrase: pass, text: root.text });
        noteCrypto.command = ["python3", root.cryptoTool, "lock", root.path,
                              lockedPath(n, root.currentNotebook)];
        noteCrypto.running = true;
    }
    function unlockNote(passphrase) {
        const pass = String(passphrase || "");
        if (root.current === "" || !isLocked(root.current) || pass === "")
            return;
        noteCrypto.mode = "decrypt";
        noteCrypto.pendingPass = pass;
        noteCrypto.payload = JSON.stringify({ passphrase: pass });
        noteCrypto.command = ["python3", root.cryptoTool, "decrypt", lockedPath(root.current, root.currentNotebook)];
        noteCrypto.running = true;
    }

}
