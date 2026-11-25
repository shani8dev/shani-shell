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
import "../Common/ToolPath.js" as ToolPath

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

    // ---- uniform service status contract ---------------------------------
    // Additive: run() opens the single in-flight guard, finished() closes it
    // and records the last success (note) or failure (error). Exit 127 means
    // the tool behind a command is not installed.
    property bool busy: false
    property string note: ""
    property string error: ""
    property string what: ""               // the command currently in flight
    function run(what, args) {
        root.what = what;
        root.busy = true;
        root.error = "";
        return true;
    }
    function finished(what, text, code) {
        root.busy = false;
        if (code === 127) {
            root.error = Tr.t("The notes service is not installed");
            return false;
        }
        if (code !== 0) {
            if (root.error === "") root.error = Tr.t("Notes could not answer");
            return false;
        }
        root.error = "";
        root.note = Tr.t("Notes updated");
        return true;
    }

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
    // out-of-band edit detection: the stamp of the file when we last read or
    // wrote it, and whether it has since changed (blocks the autosave)
    property string readStamp: ""
    property bool diskChanged: false

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
            root.finished("sync", "", code);
        }
    }
    function syncNotes() {
        if (!root.syncPath) return;
        root.run("sync", [root.syncPath]);
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
        pinnedList.running = true;      // pins are metadata, read from .pinned
        templateList.running = true;    // templates are .md files in .templates
        tagList.running = true;         // tags across every note, not just the open one
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
            root.diskChanged = false;
            statBaseline.running = true;   // remember this version of the file
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
        root.diskChanged = false;
        root.versionPreview = "";   // a preview belongs to the note it was opened for
        root.backlinkResults = [];
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
            // Never overwrite an outside edit (Chronoa, another editor):
            // compare the current file stamp with the one we read. The stat
            // callback performs the write only when they still match.
            statCheck.running = true;
        }
    }
    // mtime+size of the file at the moment we read or last wrote it
    Process {
        id: statBaseline
        command: ["sh", "-c", 'stat -c "%Y-%s" -- "$1" 2>/dev/null || echo 0', "sh", root.path]
        stdout: StdioCollector { onStreamFinished: root.readStamp = text.trim() }
    }
    Process {
        id: statCheck
        command: ["sh", "-c", 'stat -c "%Y-%s" -- "$1" 2>/dev/null || echo 0', "sh", root.path]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.readStamp !== "" && text.trim() !== root.readStamp) {
                    save.stop();               // stop autosaving; the UI offers Reload/Discard
                    root.diskChanged = true;
                    return;
                }
                root.performSave();
            }
        }
    }
    function performSave() {
        if (root.current === "")
            return;
        const dirPath = root.currentNotebook === "" ? root.dir : root.dir + "/" + root.currentNotebook;
        Quickshell.execDetached(["mkdir", "-p", dirPath]);
        root.snapshot();   // keep the previous body before overwriting it
        file.setText(root.text);
        root.syncTimer.restart();   // local-first, then mirror to the cloud mount
        statBaseline.running = true;   // our write is the new baseline
    }
    // the user chose the version on disk: drop our in-memory edits
    function reloadFromDisk() {
        if (root.current === "")
            return;
        save.stop();
        root.diskChanged = false;
        file.reload();
    }
    // the user chose our in-memory text: write it over the outside edit
    function discardExternalChange() {
        root.diskChanged = false;
        root.performSave();
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
    // deleting a notebook moves its whole folder into .trash (the same place
    // single notes go) under a unique name, so it can be put back by hand
    function deleteNotebook(name) {
        const n = validNotebook(name);
        if (n === "")
            return;
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss-zzz");
        const dest = root.trashDir + "/notebook-" + n + "-" + stamp;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && mv -f -- "$2" "$3"', "sh",
            root.trashDir, root.dir + "/" + n, dest]);
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
        property string rawQuery: ""      // operators are applied after grep
        command: ["sh", "-c", 'd="$1"; q="$2"; [ "$q" = "" ] && exit 0; grep -liF -- "$q" "$d"/*.md "$d"/*/*.md 2>/dev/null | while read -r f; do rel=${f#"$d"/}; printf "%s\\n" "${rel%.md}"; done', "sh", root.dir, query]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = root.parseQuery(grepBodies.rawQuery);
                // the plain term is grepped on disk; tag:/notebook:/name: and
                // -exclusions narrow those hits using the note metadata map
                const hits = text.trim().split("\n").filter(s => s !== "" && root.matchesOperators(s, p, ""));
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
        const raw = String(q || "").trim();
        const term = root.searchBodyTerm(raw);   // first plain/exact term only
        if (grepBodies.query !== term) {
            root.contentHits = [];
            root.bodyResults = [];
        }
        grepBodies.query = term;
        grepBodies.rawQuery = raw;
        if (term !== "")
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
        const by = root.sortBy === "title"
            ? (a, b) => String(a.name).localeCompare(String(b.name))
            : root.sortBy === "created"
                ? (a, b) => String(a.id).localeCompare(String(b.id))
                : (a, b) => b.mtime - a.mtime;   // updated: newest first
        // Pins stay at the top in every sort order, as in GNOME Notes and
        // Obsidian; otherwise the chosen order decides.
        return arr.sort((a, b) => {
            const pa = root.isPinned(a.id) ? 0 : 1;
            const pb = root.isPinned(b.id) ? 0 : 1;
            return pa !== pb ? pa - pb : by(a, b);
        });
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

    readonly property string cryptoTool: ToolPath.of(Quickshell.env("SHANI_NOTES_CRYPTO"), "note-crypto.py")
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
            // the helper encrypts only the current .md; earlier .history
            // snapshots of this note are still plaintext. Remove them so a
            // locked note leaves no readable body on disk.
            const original = String(noteCrypto.newName).replace(/\.locked$/, "");
            const key = noteId(original, root.currentNotebook).replace("/", "__");
            Quickshell.execDetached(["sh", "-c", 'rm -f -- "$1"/"$2"-*.md', "sh", root.historyDir, key]);
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

    // ---- knowledge base: pins, templates, preview, links, tags, search --------
    // Pins are metadata in <notes>/.pinned (one id per line), never written into
    // a note body. They survive a restart and float to the top of every sort.
    readonly property string pinnedFile: root.dir + "/.pinned"
    property var pinned: []
    Process {
        id: pinnedList
        command: ["sh", "-c", 'f="$1"; [ -f "$f" ] && cat -- "$f" || true', "sh", root.pinnedFile]
        stdout: StdioCollector {
            onStreamFinished: root.pinned = text.trim().split("\n").filter(s => s !== "")
        }
    }
    Process {
        id: pinnedWrite
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }
    function isPinned(id) { return root.pinned.indexOf(String(id || "")) >= 0; }
    function togglePin(id) {
        const key = String(id || "");
        if (key === "") return false;
        const list = root.pinned.slice();
        const i = list.indexOf(key);
        if (i >= 0) list.splice(i, 1);
        else list.push(key);
        root.pinned = list;
        pinnedWrite.command = ["sh", "-c", 'printf "%s\\n" "$2" > "$1"', "sh", root.pinnedFile, list.join("\n")];
        pinnedWrite.running = true;
        return i < 0;
    }

    // Templates: three built-ins plus any .md the person puts in .templates.
    // A new note is written from the template before it is opened, so the
    // editor never races an empty FileView and overwrites the template body.
    readonly property string templatesDir: root.dir + "/.templates"
    property var templateFiles: []
    Process {
        id: templateList
        command: ["sh", "-c", 'd="$1"; mkdir -p "$d"; for f in "$d"/*.md; do [ -e "$f" ] && basename "${f%.md}"; done | sort', "sh", root.templatesDir]
        stdout: StdioCollector {
            onStreamFinished: root.templateFiles = text.trim().split("\n").filter(s => s !== "")
        }
    }
    function templates() {
        const builtin = ["Meeting", "Journal", "Checklist"];
        return builtin.concat(root.templateFiles.filter(t => builtin.indexOf(t) < 0));
    }
    function templateBody(name) {
        const t = String(name || "");
        if (t === "Meeting")
            return "# Meeting\n\n- Date: \n- Attendees: \n\n## Agenda\n\n- \n\n## Notes\n\n## Action items\n\n- [ ] \n";
        if (t === "Journal")
            return "# " + Qt.formatDateTime(new Date(), "yyyy-MM-dd") + "\n\n## Today\n\n## Gratitude\n\n## Tomorrow\n";
        if (t === "Checklist")
            return "# Checklist\n\n- [ ] \n- [ ] \n";
        return "";   // a custom template is a file on disk
    }
    Process {
        id: templateCreate
        property string pendingName: ""
        property string pendingNotebook: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0 || pendingName === "") return;
            root.open(pendingName, pendingNotebook);
            root.refresh();
        }
    }
    function createFromTemplate(template, name, notebook) {
        const n = valid(name);
        const t = valid(template);
        if (n === "" || t === "") return false;
        const nb = validNotebook(notebook === undefined || notebook === null ? root.currentNotebook : notebook);
        if (notes.some(x => x.name === n && x.notebook === nb)) return false;
        const dirPath = nb === "" ? root.dir : root.dir + "/" + nb;
        const body = templateBody(t);
        templateCreate.pendingName = n;
        templateCreate.pendingNotebook = nb;
        // the template body is a shell argument, never interpolated into the
        // command, so quotes and backticks in a note cannot run anything
        templateCreate.command = body !== ""
            ? ["sh", "-c", 'mkdir -p "$1" && printf "%s" "$2" > "$3"', "sh", dirPath, body, notePath(n, nb)]
            : ["sh", "-c", 'mkdir -p "$1" && cp -f -- "$2" "$3"', "sh", dirPath, root.templatesDir + "/" + t + ".md", notePath(n, nb)];
        templateCreate.running = true;
        return true;
    }

    // Markdown preview: a deliberate small subset rendered as Qt rich text.
    // Raw HTML from a note is escaped; only our own wiki:/http(s) links are
    // activated by the surface, so a note cannot open an arbitrary scheme.
    function markdownInline(s) {
        let out = escapeHtml(s);
        out = out.replace(/`([^`]+)`/g, "<font face='monospace'>$1</font>");
        out = out.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
        out = out.replace(/\*([^*]+)\*/g, "<i>$1</i>");
        out = out.replace(/\[\[([^\[\]]+)\]\]/g, "<a href='wiki:$1'>[[$1]]</a>");
        out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, "<a href='$2'>$1</a>");
        return out;
    }
    function markdownHtml(md) {
        const lines = String(md === undefined ? root.text : md).split("\n");
        let out = "", list = false, code = false;
        lines.forEach(line => {
            if (/^\s*```/.test(line)) {
                if (list) { out += "</ul>"; list = false; }
                out += code ? "</pre>" : "<pre>";
                code = !code;
                return;
            }
            if (code) { out += escapeHtml(line) + "\n"; return; }
            const h = /^(#{1,6})\s+(.*)$/.exec(line);
            if (h) {
                if (list) { out += "</ul>"; list = false; }
                const level = Math.min(h[1].length, 6);
                out += "<h" + level + ">" + markdownInline(h[2]) + "</h" + level + ">";
                return;
            }
            if (/^\s*[-*+]\s+/.test(line)) {
                if (!list) { out += "<ul>"; list = true; }
                const item = line.replace(/^\s*[-*+]\s+/, "")
                    .replace(/^\[([ xX])\]\s*/, (m, c) => c.toLowerCase() === "x" ? "☑ " : "☐ ");
                out += "<li>" + markdownInline(item) + "</li>";
                return;
            }
            if (list) { out += "</ul>"; list = false; }
            if (/^\s*>\s?/.test(line)) {
                out += "<blockquote>" + markdownInline(line.replace(/^\s*>\s?/, "")) + "</blockquote>";
                return;
            }
            if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) { out += "<hr>"; return; }
            out += String(line).trim() === "" ? "<br>" : "<p>" + markdownInline(line) + "</p>";
        });
        if (list) out += "</ul>";
        if (code) out += "</pre>";
        return out;
    }

    // Backlinks: every note naming the open one in [[wiki links]]. The needle
    // is a grep argument, not shell text, so a note name is never a command.
    property var backlinkResults: []
    property string backlinkTarget: ""
    readonly property string backlinkScript: 'd="$1"; needle="$2"; [ "$needle" = "" ] && exit 0; grep -liF -- "$needle" "$d"/*.md "$d"/*/*.md 2>/dev/null | while read -r f; do rel=${f#"$d"/}; printf "%s\\n" "${rel%.md}"; done'
    Process {
        id: backlinkProc
        property string targetId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.backlinkResults = text.trim().split("\n").filter(s => s !== "" && s !== backlinkProc.targetId);
            }
        }
    }
    function backlinks(id) {
        const key = String(id || noteId(root.current, root.currentNotebook) || "");
        if (key === "") { root.backlinkResults = []; return root.backlinkResults; }
        root.backlinkTarget = key;
        const slash = key.indexOf("/");
        const name = slash >= 0 ? key.slice(slash + 1) : key;
        backlinkProc.targetId = key;
        backlinkProc.command = ["sh", "-c", root.backlinkScript, "sh", root.dir, "[[" + name + "]]"];
        backlinkProc.running = true;
        return root.backlinkResults;
    }
    function updateBacklinks() {
        if (root.current === "") { root.backlinkResults = []; return; }
        return root.backlinks(noteId(root.current, root.currentNotebook));
    }

    // Version preview: history() still lists the dated copies; a version can
    // now be read before it replaces the note, and stepped through with keys.
    property string versionPreview: ""
    FileView {
        id: versionView
        path: ""
        printErrors: false
        onLoaded: root.versionPreview = text()
        onLoadFailed: root.versionPreview = Tr.t("This version could not be read")
    }
    function previewVersion(path) {
        if (!path) { root.versionPreview = ""; return; }
        versionView.path = String(path);
        versionView.reload();
    }

    // Tags: the current note's tags() drives the chips; tagList collects the
    // tags of every note with its id so search operators and the tag picker
    // work across the whole vault, not just the open note.
    property var noteTags: ({})
    property var allTagsList: []
    Process {
        id: tagList
        command: ["sh", "-c", 'd="$1"; for f in "$d"/*.md "$d"/*/*.md; do [ -e "$f" ] || continue; rel=${f#"$d"/}; t=$(grep -hoE "#[A-Za-z0-9_-]+" -- "$f" | sort -u | paste -sd, -); printf "%s\\t%s\\n" "${rel%.md}" "$t"; done', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const byNote = {}, all = {};
                text.trim().split("\n").forEach(line => {
                    const i = line.indexOf("\t");
                    if (i <= 0) return;
                    byNote[line.slice(0, i)] = line.slice(i + 1);
                    line.slice(i + 1).split(",").forEach(t => { if (t !== "") all[t] = true; });
                });
                root.noteTags = byNote;
                root.allTagsList = Object.keys(all).sort();
            }
        }
    }
    function validTag(tag) {
        const m = /^#?([A-Za-z0-9_-]+)$/.exec(String(tag || "").trim());
        return m ? "#" + m[1] : "";
    }
    function addTag(tag) {
        const t = validTag(tag);
        if (t === "" || root.current === "" || tags().indexOf(t) >= 0) return false;
        set(String(root.text).replace(/\s*$/, "") + "\n" + t);
        return true;
    }
    function removeTag(tag) {
        const t = validTag(tag);
        if (t === "" || root.current === "") return false;
        const before = String(root.text);
        const after = before.split("\n").map(line =>
            line.replace(new RegExp(t + "(?![A-Za-z0-9_-])", "g"), "").replace(/\s+$/, "")).join("\n");
        if (after === before) return false;
        set(after);
        return true;
    }

    // Search operators: "two words", tag:x, notebook:x, name:x and -excluded.
    // Quoted phrases and the operators narrow name/notebook/preview/tag data;
    // searchBodies() sends only the first plain term to grep and applies the
    // same predicate to its hits, so body search and the list agree.
    function parseQuery(q) {
        const out = { text: [], tags: [], notebooks: [], names: [], exclude: [], exact: [] };
        const tokens = String(q || "").match(/"[^"]*"|\S+/g) || [];
        tokens.forEach(raw => {
            const t = String(raw).trim();
            if (t.length > 2 && t.charAt(0) === '"' && t.charAt(t.length - 1) === '"') {
                out.exact.push(t.slice(1, -1).toLowerCase());
                return;
            }
            if (t.length > 1 && t.charAt(0) === "-") {
                out.exclude.push(t.slice(1).toLowerCase());
                return;
            }
            const op = /^(tag|notebook|name):(.+)$/i.exec(t);
            if (op) {
                const v = op[2].toLowerCase().replace(/^#/, "");
                const kind = op[1].toLowerCase();
                if (kind === "tag") out.tags.push(v);
                else if (kind === "notebook") out.notebooks.push(v);
                else out.names.push(v);
                return;
            }
            out.text.push(t.toLowerCase());
        });
        return out;
    }
    function searchBodyTerm(q) {
        const p = root.parseQuery(q);
        if (p.exact.length) return p.exact[0];
        if (p.text.length) return p.text[0];
        if (p.tags.length) return "#" + p.tags[0];    // tag:x alone finds tagged notes
        return "";
    }
    function matchesOperators(id, p, notebook, tagFilter) {
        const key = String(id || "");
        const slash = key.indexOf("/");
        const name = slash >= 0 ? key.slice(slash + 1) : key;
        const nb = slash >= 0 ? key.slice(0, slash) : "";
        const hay = (name + " " + nb + " " + (root.previews[key] || "")).toLowerCase();
        const tags = (root.noteTags[key] || "").toLowerCase();
        if (notebook && nb !== notebook) return false;
        const tf = String(tagFilter || "").replace(/^#/, "").toLowerCase();
        if (tf !== "" && tags.indexOf("#" + tf) < 0) return false;
        if (p.tags.some(t => tags.indexOf("#" + t) < 0)) return false;
        if (p.notebooks.some(v => nb.toLowerCase().indexOf(v) < 0)) return false;
        if (p.names.some(v => name.toLowerCase().indexOf(v) < 0)) return false;
        if (p.exact.some(e => hay.indexOf(e) < 0)) return false;
        if (p.text.some(t => hay.indexOf(t) < 0)) return false;
        if (p.exclude.some(x => hay.indexOf(x) >= 0 || tags.indexOf("#" + x) >= 0)) return false;
        return true;
    }
    function filterNotes(q, notebook, tagFilter) {
        const p = root.parseQuery(q);
        const nb = validNotebook(notebook || "");
        return notes.filter(n => root.matchesOperators(n.id, p, nb, tagFilter));
    }

    // Markdown export is a copy of the plaintext (also for a locked note);
    // HTML export above stays as it was. Both go through a native save dialog.
    property string lastExportedMd: ""
    FileView {
        id: mdExportView
        path: ""
        printErrors: false
    }
    function exportMarkdown(dest) {
        if (root.current === "") return "";
        const target = dest ? String(dest)
            : notePath(root.current, root.currentNotebook).replace(/\.md$/, ".md");
        if (target === "") return "";
        mdExportView.path = target;
        mdExportView.setText(root.text);
        root.lastExportedMd = target;
        return target;
    }
    function exportMarkdownDialog() {
        if (root.current === "") return;
        FilePicker.open({ mode: "save", title: Tr.t("Export note as Markdown"),
            defaultName: root.current + ".md", filters: ["md", "txt"],
            onPicked: paths => { if (paths.length) root.exportMarkdown(paths[0]); } });
    }

    // Notebooks are folders: move changes the path, copy keeps the original.
    // Both refuse an existing destination, so nothing is silently overwritten.
    Process {
        id: noteMove
        property bool reloadOpen: false
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (code === 0 && reloadOpen) file.reload();
            reloadOpen = false;
            root.refresh();
        }
    }
    function changeNotebook(name, fromNotebook, toNotebook, move) {
        const n = valid(name);
        const from = validNotebook(fromNotebook);
        const to = validNotebook(toNotebook);
        if (n === "" || from === to) return false;
        if (notes.some(x => x.name === n && x.notebook === to)) return false;
        const dirPath = to === "" ? root.dir : root.dir + "/" + to;
        noteMove.command = ["sh", "-c", 'mkdir -p "$1" && ' + (move ? 'mv -f -- "$2" "$3"' : 'cp -f -- "$2" "$3"'),
                            "sh", dirPath, notePath(n, from), notePath(n, to)];
        noteMove.reloadOpen = move && root.current === n && root.currentNotebook === from;
        if (noteMove.reloadOpen) {
            save.stop();
            root.currentNotebook = to;
        }
        noteMove.running = true;
        return true;
    }
    function moveToNotebook(name, fromNotebook, toNotebook) {
        return root.changeNotebook(name, fromNotebook, toNotebook, true);
    }
    function copyToNotebook(name, fromNotebook, toNotebook) {
        return root.changeNotebook(name, fromNotebook, toNotebook, false);
    }
}
