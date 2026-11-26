pragma Singleton
// Archives (Modules/Archives shows it): what is inside a zip, a tar (gz, xz,
// zst, bz2), a 7z or an ISO, and taking it out. libarchive's bsdtar does the
// reading, so every format it knows is known here.
//
// A password: bsdtar is always given one (--passphrase), a placeholder until
// a person types the real one. Given none at all, bsdtar asks for it on the
// terminal it does not have, over and over (measured: an endless "Enter
// passphrase:"); given a wrong one it stops and says "Incorrect passphrase",
// which is how a protected archive is told apart here. (bsdtar 3.8 ignores the
// LIBARCHIVE_PASSPHRASE variable, measured, so the argument it is.)
//
// One item can be taken out on its own (beside the archive, never over a
// file), and archives are made too: Files' "Compress" (zip, tar.gz, tar.xz,
// 7z), written as a temporary file and renamed when whole.
//
// A lone compressed file (notes.txt.gz, a .xz, .zst, .bz2, .lz, .lzma, .lz4 that
// is not a tar) is no archive to bsdtar (it fails, measured); it is shown as
// the one file inside it and taken out with
// libarchive's bsdcat, which reads every one of those (measured).
//
// Extracting never writes over anything: the files go into a new folder
// named after the archive ("photos.zip" -> "photos", or "photos (2)" when
// that is taken). Every entry is written by bridge/zipcrypt.py, which refuses
// paths that climb out ("../", absolute) and links/devices, so an archive
// cannot place a file or a symlink outside that folder.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ServiceRun.js" as ServiceRun
import "../Common/Format.js" as Format
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root

    property bool shown: false
    property string file: ""              // the archive open
    readonly property string name: file.split("/").pop()
    property var entries: []              // [{ path, size, dir }]
    property real totalSize: 0
    property bool reading: false
    property bool extracting: false
    property string error: ""
    // ---- uniform service status contract ---------------------------------
    // Additive: run() opens the single in-flight guard, finished() closes it
    // and records the last success (note) or failure (error). Exit 127 means
    // the archive tool is not installed.
    property bool busy: false
    property string note: ""               // last successful job
    property string what: ""               // the command currently in flight
    function run(what, args) { return ServiceRun.begin(root, what); }
    function finished(what, text, code) {
        root.busy = false;
        if (code === 127) {
            root.error = Tr.t("The archive tool is not installed");
            return false;
        }
        if (code !== 0) {
            if (root.error === "")
                root.error = Tr.t("Could not use the archive tool");
            return false;
        }
        root.error = "";
        root.note = Tr.t("Archive ready");
        return true;
    }
    property string extractedTo: ""       // the folder the last extraction made
    property string passphrase: ""        // what a person typed for a protected archive
    property bool needsPassword: false    // bsdtar said the passphrase is wrong (or none was given)
    property string retry: ""             // what to do again once the password is given: "list" | "extract" | "one:<path>"
    property string made: ""              // the archive the last Compress made
    property bool creating: false
    // never empty: bsdtar would ask on a terminal it does not have, forever
    readonly property string pass: passphrase || "\u0001no-password"
    readonly property bool available: tool.found
    readonly property string extractTool: ToolPath.of(Quickshell.env("SHANI_ARCHIVE_EXTRACT_TOOL"), "zipcrypt.py")
    property bool single: false           // a lone compressed file, not an archive (bsdcat takes it out)
    readonly property var singleExts: ["gz", "bz2", "xz", "zst", "lz", "lzma", "lz4", "Z"]
    readonly property string singleExt: { const m = /\.([A-Za-z0-9]+)$/.exec(name); return m && singleExts.indexOf(m[1]) >= 0 ? m[1] : ""; }
    readonly property var types: ["zip", "tar", "gz", "tgz", "xz", "txz", "zst", "bz2", "tbz2", "7z", "iso", "rar", "cpio", "jar", "apk", "deb", "rpm", "cab", "lz4", "lzma"]

    // ---- entry selection + taking several entries out at once -------------
    // Only paths that are actually listed can be selected, and a path is never
    // held twice (a filtered list and a Ctrl/Shift-click can overlap).
    property var selection: []            // the chosen entry paths, in list order
    property string selectionAnchor: ""   // where a Shift-click range starts
    property var batchPaths: []           // the deduped queue for "extract selected"
    property int batchIndex: 0            // next entry to take out
    property var batchDone: []            // paths that came out
    property var batchFailed: []          // [{ path, error }], one per bad entry
    property string batchSummary: ""      // what the window reports at the end
    property bool modified: false         // this archive changed since it was opened

    // ---- recent archives, browsing and view state --------------------------
    // Session-local, like File Roller's recent menu: newest first, no duplicates,
    // capped so a long day cannot fill the header. Nothing is written to disk.
    property var recent: []                // paths of archives opened or made
    property string currentDir: ""         // "" is the root of the archive
    property string sortOrder: "name"      // "name" | "size"
    property string overwritePolicy: "rename"  // "rename" | "overwrite" | "skip"
    property bool wasProtected: false     // this archive asked for a password
    property bool testing: false          // an integrity pass is running
    property string testResult: ""        // the last integrity result

    function noteRecent(path) {
        const p = String(path || "");
        if (p === "") return;
        const next = [p];
        for (const r of root.recent)
            if (r !== p && next.indexOf(r) < 0) next.push(r);
        root.recent = next.slice(0, 8);
    }
    function clearRecent() { root.recent = []; }
    function setSortOrder(order) { root.sortOrder = order === "size" ? "size" : "name"; }
    function setOverwritePolicy(policy) {
        root.overwritePolicy = policy === "overwrite" || policy === "skip" ? policy : "rename";
    }

    // Only the entries directly inside currentDir, plus one synthetic folder
    // for each subdirectory (an archive need not carry explicit dir entries).
    // `list` is the already-filtered visible set, so search and browsing compose.
    function entriesHere(list) {
        const all = list && list.length !== undefined ? list : root.entries;
        const d = root.currentDir;
        const prefix = d === "" ? "" : d + "/";
        const out = [], seen = {};
        for (const e of all) {
            if (e.path.indexOf(prefix) !== 0) continue;
            const rest = e.path.slice(prefix.length);
            if (rest === "") continue;
            const slash = rest.indexOf("/");
            if (slash < 0) out.push(e);
            else {
                const folder = prefix + rest.slice(0, slash);
                if (!seen[folder]) {
                    seen[folder] = true;
                    out.push({ path: folder, size: 0, dir: true, virtual: true });
                }
            }
        }
        out.sort((a, b) => {
            if (root.sortOrder === "size" && !a.dir && !b.dir && b.size !== a.size)
                return b.size - a.size;
            if (a.dir !== b.dir) return a.dir ? -1 : 1;
            return a.path.localeCompare(b.path);
        });
        return out;
    }
    function browse(path) {
        if (path) root.currentDir = String(path).replace(/\/$/, "");
    }
    function up() {
        const d = root.currentDir;
        root.currentDir = d.indexOf("/") < 0 ? "" : d.slice(0, d.lastIndexOf("/"));
    }

    function open(arg) {
        root.shown = true;
        let path = String(arg || "").trim();
        if (path.startsWith("file://"))
            path = decodeURIComponent(path.substring(7));
        if (path === "")
            return;
        if (!path.startsWith("/"))
            path = (Quickshell.env("HOME") || "") + "/" + path;
        root.file = path;
        root.noteRecent(path);
        root.currentDir = "";
        root.entries = [];
        root.totalSize = 0;
        root.error = "";
        root.extractedTo = "";
        root.passphrase = "";
        root.needsPassword = false;
        root.wasProtected = false;
        root.testResult = "";
        root.single = false;
        root.toCompress = [];
        root.abortBatch();
        root.clearSelection();
        root.modified = false;          // a reopened file is the saved one
        list();
    }
    function list() {
        root.run("list", [root.file]);
        root.reading = true;
        lister.command = ["bsdtar", "--passphrase", root.pass, "-tvf", root.file];
        lister.running = true;
    }
    // a window can go away while a job is still running; stop it here, not in
    // the UI, so closing is the same as cancelling for every caller
    function cancel() {
        root.abortBatch();
        if (lister.running) lister.running = false;
        if (singleSize.running) singleSize.running = false;
        if (singleOut.running) singleOut.running = false;
        if (hardOne.running) hardOne.running = false;
        if (extractor.running) extractor.running = false;
        if (spaceProbe.running) spaceProbe.running = false;
        if (maker.running) maker.running = false;
        if (appender.running) appender.running = false;
        if (tester.running) tester.running = false;
        root.reading = false;
        root.extracting = false;
        root.creating = false;
        root.appending = false;
        root.testing = false;
        root.extractWhenRead = false;
        root.probeThenExtract = false;
    }
    function close() {
        cancel();
        shown = false;
        passphrase = "";
        needsPassword = false;
        retry = "";
        newPass = "";
        testResult = "";
        wasProtected = false;
        currentDir = "";
        clearSelection();
        modified = false;
    }

    // ---- selection ---------------------------------------------------------
    function isSelected(path) { return root.selection.indexOf(path) >= 0; }
    function clearSelection() { root.selection = []; root.selectionAnchor = ""; }
    // The visible list is the authority: a hidden entry cannot be selected and
    // a path repeated in the input is only held once. This is the one place a
    // selection array is built, so every way in is deduped the same way.
    function setSelection(paths, visible) {
        const allowed = visible && visible.length !== undefined ? visible : root.entries.map(e => e.path);
        const chosen = [];
        for (const p of (paths || []))
            if (allowed.indexOf(p) >= 0 && chosen.indexOf(p) < 0) chosen.push(p);
        root.selection = chosen;
        root.selectionAnchor = chosen.length ? chosen[chosen.length - 1] : "";
    }
    function selectAll(visible) { root.setSelection(visible, visible); }
    function selectEntry(path, mode, visible) {
        const paths = visible && visible.length !== undefined ? visible : root.entries.map(e => e.path);
        if (paths.indexOf(path) < 0) return;
        if (mode === "range") {
            const anchor = paths.indexOf(root.selectionAnchor) >= 0 ? root.selectionAnchor : path;
            const a = paths.indexOf(anchor), b = paths.indexOf(path);
            root.setSelection(paths.slice(Math.min(a, b), Math.max(a, b) + 1), paths);
            return;
        }
        if (mode === "toggle") {
            const chosen = root.selection.slice();
            const at = chosen.indexOf(path);
            if (at >= 0) chosen.splice(at, 1); else chosen.push(path);
            root.setSelection(chosen, paths);   // keeps the anchor on a selected entry
            return;
        }
        root.setSelection([path], paths);
    }

    Process {
        id: tool
        property bool found: false
        running: true
        command: ["sh", "-c", 'command -v bsdtar >/dev/null 2>&1 || exit 127']
        onExited: code => {
            found = code === 0;
            root.finished("probe", "", code);
        }
    }

    // "-rw-r--r--  0 user group  1234 Nov 11 18:00 dir/file" - the name is what follows the eighth field
    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let total = 0;
                for (const line of text.split("\n")) {
                    const m = /^(\S+)\s+\S+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+\S+\s(.*)$/.exec(line);
                    if (!m)
                        continue;
                    const kind = m[1].charAt(0);
                    // only regular files and folders: a link or device is never
                    // shown, selectable, or handed to an extractor
                    if (kind !== "-" && kind !== "d")
                        continue;
                    const dir = kind === "d";
                    const path = m[3];
                    const size = dir ? 0 : parseInt(m[2]);
                    total += size;
                    out.push({ path: path.replace(/\/$/, ""), size: size, dir: dir });
                }
                root.entries = out;
                root.totalSize = total;
            }
        }
        stderr: StdioCollector { id: listErr }
        onExited: code => {
            root.finished("list", listErr.text, code);
            root.reading = false;
            if (code === 127) { root.extractWhenRead = false; return; }
            if (code !== 0) {
                root.extractWhenRead = false;
                if (root.askPassword(listErr.text, "list"))
                    return;
                // not by bsdtar's words: a lone .gz says "Unrecognized archive format", a lone
                // .xz of text says "Missing type keyword in mtree specification" (it reads
                // the text as an mtree list - measured). The probe's magic check decides.
                if (root.singleExt !== "" && !/\.tar\.[A-Za-z0-9]+$/.test(root.name)) {
                    root.single = true;
                    root.reading = true;
                    // bsdcat passes ANY bytes through (measured: plain text and random
                    // data both exit 0), so the file must start with a compressor's magic
                    singleSize.command = ["bash", "-c", 'set -o pipefail
                        m=$(od -An -tx1 -N6 -- "$1" | tr -d " \n")
                        case "$m" in 1f8b*|425a68*|fd377a585a00|28b52ffd*|4c5a4950*|04224d18*|5d0000*|1f9d*) ;; *) exit 2;; esac
                        bsdcat -- "$1" | wc -c', "bash", root.file];
                    singleSize.running = true;
                    return;
                }
                root.error = Tr.t("Not an archive that can be read") + ": " + root.name;
            } else if (root.extractWhenRead) {
                root.extractWhenRead = false;
                root.extract("");
            }
        }
    }

    // a lone compressed file: the one file inside, at its real size
    Process {
        id: singleSize
        stdout: StdioCollector {
            onStreamFinished: {
                const size = parseInt(text.trim()) || 0;
                root.entries = [{ path: root.name.slice(0, -(root.singleExt.length + 1)), size: size, dir: false }];
                root.totalSize = size;
            }
        }
        onExited: code => {
            root.reading = false;
            if (code !== 0) {
                root.single = false;
                root.entries = [];
                root.error = Tr.t("Not an archive that can be read") + ": " + root.name;
            } else {
                // bsdtar's refusal was expected here; the probe succeeded, so
                // the earlier "Could not use the archive tool" is not an error
                root.error = "";
                if (root.extractWhenRead) {
                    root.extractWhenRead = false;
                    root.extract("");
                }
            }
        }
    }
    // the one file of a lone compressed file, into `dir` under a name not taken (never over a file)
    function extractSingle(dir, done) {
        root.error = "";
        root.extractedTo = "";
        root.extracting = true;
        singleOut.command = ["sh", "-c", 'n=$3; case "$n" in *.*) b=${n%.*}; e=.${n##*.};; *) b=$n; e=;; esac
            d="$1/$n"; i=2; while [ -e "$d" ]; do d="$1/$b ($i)$e"; i=$((i+1)); done
            t=$(mktemp "$1/.shani-extract.XXXXXX") || exit 1
            bsdcat -- "$2" > "$t" || { s=$?; rm -f "$t"; exit $s; }
            mv -- "$t" "$d" && printf "%s" "$d"',
            "sh", dir, root.file, root.entries.length ? root.entries[0].path : root.name];
        singleOut.running = true;
    }
    Process {
        id: singleOut
        stdout: StdioCollector { id: singleMade }
        stderr: StdioCollector { id: singleErr }
        onExited: code => {
            root.extracting = false;
            if (code === 0) root.extractedTo = singleMade.text;
            else root.error = Tr.t("Could not extract") + ": " + (singleErr.text.trim().split("\n").pop() || root.name);
        }
    }

    // bsdtar's words for "this needs a password": ask for it, and what to redo after
    function askPassword(stderr, what) {
        if (!/passphrase|encrypt/i.test(stderr))
            return false;
        root.error = root.passphrase ? Tr.t("That password is not right") : "";
        root.needsPassword = true;
        root.wasProtected = true;
        root.retry = what;
        return true;
    }
    // the hardened extractor reports a wrong password in its JSON; bsdtar's
    // wording is kept as a fallback for the paths that still use it
    function askResult(result, stderr, what) {
        if (result && result.wrongPassword) {
            root.error = root.passphrase ? Tr.t("That password is not right") : "";
            root.needsPassword = true;
            root.wasProtected = true;
            root.retry = what;
            return true;
        }
        return root.askPassword(stderr, what);
    }
    function unlock(pw) {
        root.passphrase = pw;
        root.needsPassword = false;
        root.error = "";
        if (root.retry === "list") list();
        else if (root.retry === "extract") extract("");
        else if (root.retry === "batch") { root.retry = ""; root.extracting = true; root.nextBatch(); }
        else if (root.retry === "test") { root.retry = ""; root.testArchive(); }
        else if (root.retry.indexOf("one:") === 0) extractOne(root.retry.slice(4));
    }

    // one item (a file or a folder) beside the archive, under a name not taken.
    // Only a listed entry can be selected, and the hardened reader gets that
    // exact name, so a link planted beside it is never written.
    function extractOne(entry) {
        if (root.file === "" || root.extracting || !entry)
            return;
        if (root.single) { extractSingle(root.file.substring(0, root.file.lastIndexOf("/")), ""); return; }
        if (!root.entries.some(e => e.path === entry)) {
            root.error = Tr.t("Could not extract") + ": " + entry;
            return;
        }
        root.error = "";
        root.extractedTo = "";
        root.batchSummary = "";
        root.extracting = true;
        hardOne.target = entry;
        hardOne.payload = root.pass + "\n";
        hardOne.command = ["sh", "-c", 'p=$1; t=$(mktemp -d "$p/.shani-extract.XXXXXX") || exit 1
            python3 "$2" extract "$3" "$t/x" "$4" || { s=$?; rm -rf "$t"; exit $s; }
            n=${4##*/}; case "$n" in *.*) b=${n%.*}; e=.${n##*.};; *) b=$n; e=;; esac
            d="$p/$n"; i=2; while [ -e "$d" ]; do d="$p/$b ($i)$e"; i=$((i+1)); done
            mv -- "$t/x/$4" "$d" && rm -rf "$t" && printf "%s" "$d"',
            "sh", root.file.substring(0, root.file.lastIndexOf("/")), root.extractTool, root.file, entry];
        hardOne.stdinEnabled = true;
        hardOne.running = true;
    }
    Process {
        id: hardOne
        property string target: ""
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload); payload = ""; stdinEnabled = false; }
        stdout: StdioCollector { id: oneMade }
        stderr: StdioCollector { id: oneErr }
        onExited: code => {
            root.extracting = false;
            const lines = oneMade.text.trim().split("\n");
            let result = {};
            try { result = JSON.parse(lines[0]) || {}; } catch (e) {}
            if (root.askResult(result, oneErr.text, "one:" + hardOne.target))
                return;
            if (code === 0) root.extractedTo = lines[lines.length - 1];
            else root.error = Tr.t("Could not extract") + ": " + (result.error || oneErr.text.trim().split("\n").pop() || hardOne.target);
        }
    }

    // ---- several selected entries, into one folder -------------------------
    // A batch is a queue, not a loop of extractOne(): that call is asynchronous
    // and refuses to run while another extraction is in flight. Each entry goes
    // through the same hardened reader as "extract one"; one bad entry is
    // recorded and the next still runs. A wrong password pauses the queue at
    // that entry, so Unlock resumes without redoing the ones already out.
    function abortBatch() {
        if (batchOne.running) batchOne.running = false;
        root.extracting = false;
        root.probeThenExtract = false;
        root.batchPaths = [];
        root.batchIndex = 0;
        root.batchDone = [];
        root.batchFailed = [];
        root.batchSummary = "";
        root.probeKind = "";
        root.probeSize = 0;
    }
    function batchRefused(why) {
        root.error = why;
        root.batchSummary = Tr.t("Nothing") + " — " + why;
        root.batchPaths = [];
        root.batchIndex = 0;
        root.probeKind = "";
    }
    function extractSelected(paths, where) {
        const allowed = root.entries.map(e => e.path);
        const wanted = [];
        for (const p of (paths || []))
            if (allowed.indexOf(p) >= 0 && wanted.indexOf(p) < 0) wanted.push(p);
        if (!wanted.length || root.file === "" || root.extracting || root.probeThenExtract)
            return;
        if (root.single) { extractSingle(where || root.file.substring(0, root.file.lastIndexOf("/")), ""); return; }
        root.abortBatch();
        root.error = "";
        root.extractedTo = "";
        root.batchPaths = wanted;
        let bytes = 0;
        for (const p of wanted) {
            const e = root.entries.find(x => x.path === p);
            bytes += e ? e.size : 0;          // uncompressed size of just these entries
        }
        root.probeSize = bytes;
        root.probeKind = "batch";
        root.probeThenExtract = true;
        root.probeWhere = where || root.file.substring(0, root.file.lastIndexOf("/"));
        spaceProbe.command = ["sh", "-c", 'printf "%s %s\\n" "$(df -PB1 -- "$1" | tail -1 | awk "{print \\$4}")" "$(stat -c %s -- "$2" || echo 0)"',
                              "sh", root.probeWhere, root.file];
        spaceProbe.running = true;
    }
    function batchExtractNow() {
        root.extracting = true;
        root.nextBatch();
    }
    function nextBatch() {
        if (root.batchIndex >= root.batchPaths.length) { root.finishBatch(); return; }
        const entry = root.batchPaths[root.batchIndex];
        batchOne.payload = root.pass + "\n";
        batchOne.command = ["sh", "-c", 'p=$1; t=$(mktemp -d "$p/.shani-extract.XXXXXX") || exit 1
            python3 "$2" extract "$3" "$t/x" "$4" || { s=$?; rm -rf "$t"; exit $s; }
            n=${4##*/}; case "$n" in *.*) b=${n%.*}; e=.${n##*.};; *) b=$n; e=;; esac
            d="$p/$n"; i=2; while [ -e "$d" ]; do d="$p/$b ($i)$e"; i=$((i+1)); done
            mv -- "$t/x/$4" "$d" && rm -rf "$t" && printf "%s" "$d"',
            "sh", root.probeWhere, root.extractTool, root.file, entry];
        batchOne.stdinEnabled = true;
        batchOne.running = true;
    }
    function finishBatch() {
        root.extracting = false;
        const done = root.batchDone.length, failed = root.batchFailed.length;
        root.batchSummary = Tr.t("%1 selected").arg(done + failed) + " — " + Tr.t("Done") + ": " + done
            + (failed ? "  ·  " + Tr.t("%1 failed").arg(failed) : "");
        root.extractedTo = root.probeWhere;
        if (failed)
            root.error = root.batchFailed.map(x => x.path + ": " + x.error).join("  ·  ");
        root.batchPaths = [];
        root.batchIndex = 0;
        root.probeKind = "";
    }
    Process {
        id: batchOne
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload); payload = ""; stdinEnabled = false; }
        stdout: StdioCollector { id: oneBatchOut }
        stderr: StdioCollector { id: oneBatchErr }
        onExited: code => {
            if (root.batchIndex >= root.batchPaths.length) return;   // cancelled mid-entry
            const lines = oneBatchOut.text.trim().split("\n");
            let result = {};
            try { result = JSON.parse(lines[0]) || {}; } catch (e) {}
            const entry = root.batchPaths[root.batchIndex];
            if ((result && result.wrongPassword) || /passphrase|encrypt/i.test(oneBatchErr.text)) {
                root.needsPassword = true;
                root.error = root.passphrase ? Tr.t("That password is not right") : "";
                root.retry = "batch";
                root.extracting = false;
                return;                     // stay on this entry until Unlock
            }
            // assign new arrays so bindings on .length update without relying on
            // a separate property being reassigned later
            if (code === 0) root.batchDone = root.batchDone.concat([entry]);
            else root.batchFailed = root.batchFailed.concat([{ path: entry,
                error: (result && result.error) || oneBatchErr.text.trim().split("\n").pop() || Tr.t("Could not extract") }]);
            root.batchIndex++;
            root.nextBatch();
        }
    }

    // Compress: the chosen files into one archive beside them, under a free name
    property bool extractWhenRead: false  // Files' "Extract here": as soon as the list is in
    function extractHere(path) { open(path); extractWhenRead = true; }
    property var toCompress: []           // what Files asked to compress (the window shows the choices)
    property string format: "zip"
    property string newPass: ""           // password for the archive about to be made
    function createAsk(paths) {
        toCompress = typeof paths === "string" ? [paths] : Array.from(paths || []).map(String);
        // a task of its own: no archive open underneath it
        file = "";
        currentDir = "";
        entries = [];
        totalSize = 0;
        extractedTo = "";
        needsPassword = false;
        wasProtected = false;
        testResult = "";
        made = "";
        error = "";
        newPass = "";
        root.abortBatch();
        root.clearSelection();
        root.modified = false;
        shown = true;
    }
    function defaultName(paths) {
        return !paths || !paths.length ? "" : paths.length === 1 ? paths[0].split("/").pop().replace(/\.[^.\/]+$/, "") : Tr.t("Archive");
    }
    readonly property var formats: [{ ext: "zip", label: "ZIP" }, { ext: "tar.gz", label: "tar.gz" }, { ext: "tar.xz", label: "tar.xz" }, { ext: "7z", label: "7z" }]
    function create(given, ext, name, pass) {
        // a list, however it came (a JS array, a QML list, one path)
        const paths = typeof given === "string" ? [given] : Array.from(given || []).map(String);
        if (!paths.length || root.creating)
            return;
        const parent = paths[0].substring(0, paths[0].lastIndexOf("/")) || "/";
        const stem = (name || defaultName(paths)).replace(/\//g, "-");
        const pw = pass !== undefined ? pass : root.newPass;
        // A tar is a container with no encryption of its own. Silently dropping
        // a requested password would hand back an archive anyone can read, so
        // refuse instead of writing one that only looks protected.
        if (pw && ext !== "zip" && ext !== "7z") {
            root.error = Tr.t("A password cannot protect a tar archive — use ZIP or 7z");
            return;
        }
        root.error = "";
        root.made = "";
        root.creating = true;
        // a password is a real one for zip and 7z: zip encrypts the contents
        // (AES, for a reader that can; ZipCrypto for one that cannot) and 7z
        // encrypts by default. A tar is a container with no encryption of its
        // own, so it gets none. The options go through the command line as
        // separate arguments, so a passphrase with spaces or quotes survives.
        const opts = pw
            ? (ext === "zip" ? ["--options", "zip:encryption=aes256", "--passphrase", pw]
                              : ext === "7z" ? ["--passphrase", pw] : [])
            : ["--passphrase", "\u0001no-password"];
        // Inputs may come from different folders: stage each full path under a
        // unique name in the temp dir, then archive from there. Copying (rather
        // than symlinking) keeps bsdtar from storing the link itself.
        maker.command = ["bash", "-c", 'p=$1; s=$2; x=$3; shift 3
            p=$(cd "$p" && pwd) || exit 1
            opts=(); while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do opts+=("$1"); shift; done
            [ "$#" -gt 0 ] && shift
            t=$(mktemp -d "$p/.shani-archive.XXXXXX") || exit 1
            t=$(cd "$t" && pwd) || { rm -rf "$t"; exit 1; }
            stage="$t/stage"; mkdir -p "$stage" || { rm -rf "$t"; exit 1; }
            names=()
            for src in "$@"; do
                b=${src##*/}; [ -n "$b" ] || b=item
                n=$b; i=2; while [ -e "$stage/$n" ]; do n="$b ($i)"; i=$((i+1)); done
                cp -a -- "$src" "$stage/$n" || { r=$?; rm -rf "$t"; exit $r; }
                names+=("$n")
            done
            cd "$stage" || { rm -rf "$t"; exit 1; }
            bsdtar -acf "$t/$s.$x" "${opts[@]}" -- "${names[@]}" || { r=$?; rm -rf "$t"; exit $r; }
            d="$p/$s.$x"; i=2; while [ -e "$d" ]; do d="$p/$s ($i).$x"; i=$((i+1)); done
            mv -- "$t/$s.$x" "$d" && rm -rf "$t" && printf "%s" "$d"',
            "bash", parent, stem, ext || "zip"].concat(opts, ["--"], paths);
        maker.running = true;
    }
    Process {
        id: maker
        stdout: StdioCollector { id: madeOut }
        stderr: StdioCollector { id: makeErr }
        onExited: code => {
            root.creating = false;
            if (code === 0) { root.made = madeOut.text; root.noteRecent(root.made); }
            else root.error = Tr.t("Could not make the archive") + ": " + (makeErr.text.trim().split("\n").pop() || "");
        }
    }

    // ---- adding to an archive that is already open -------------------------
    // What can be added to depends on the tool: libarchive cannot append to a
    // zip at all ("Unrecognized archive format" reading one back for -r) and
    // refuses a compressed tar, so a zip goes through bridge/zipadd.py (the
    // standard library, which can) and a plain tar through bsdtar itself. The
    // rest - 7z, iso, rar, anything compressed - is refused in words, because
    // a silent no would be worse.
    readonly property var appendable: ["zip", "jar", "apk", "tar", "cpio"]
    readonly property string appendExt: {
        const n = root.name.toLowerCase();
        for (const e of root.appendable)
            if (n.endsWith("." + e)) return e;
        return "";
    }
    readonly property bool canAppend: root.appendExt !== "" && root.file !== "" && !root.single
    property bool appending: false
    property string zipTool: ToolPath.of(Quickshell.env("SHANI_ZIPADD_TOOL"), "zipadd.py")

    function append(paths) {
        // dedupe and never add the archive to itself: a repeated path would be
        // stored twice, and adding the archive to itself can corrupt it
        const given = (typeof paths === "string" ? [paths] : Array.from(paths || []).map(String))
            .filter(p => p && p !== root.file);
        const list = given.filter((p, i) => given.indexOf(p) === i);
        if (!list.length || !root.canAppend || root.appending)
            return;
        root.error = "";
        root.appending = true;
        // jar and apk are zip containers too: bsdtar -rf cannot append to
        // them, so they must go through the same zip writer as .zip.
        if (["zip", "jar", "apk"].indexOf(root.appendExt) >= 0)
            appender.command = ["python3", root.zipTool, "add", root.file].concat(list);
        else
            appender.command = ["sh", "-c", 'f=$1; p=$2; pp=$3; shift 3; cd "$p" || exit 1
                bsdtar --passphrase "$pp" -rf "$f" -- "$@" || exit $?',
                "sh", root.file, root.file.substring(0, root.file.lastIndexOf("/")) || "/", root.pass]
                .concat(list);
        appender.running = true;
    }

    Process {
        id: appender
        stdout: StdioCollector { id: appendOut }
        stderr: StdioCollector { id: appendErr }
        onExited: code => {
            root.appending = false;
            if (code === 0) {
                if (appendOut.text.trim().indexOf('"error"') >= 0) {
                    let why = "";
                    try { why = (JSON.parse(appendOut.text) || {}).error || ""; } catch (e) {}
                    root.error = why === "protected"
                        ? Tr.t("A protected archive cannot be added to")
                        : (why || Tr.t("Could not add to the archive"));
                    return;
                }
                root.modified = true;       // the file on disk changed; reopen to refresh
                root.list();
            } else
                root.error = Tr.t("Could not add to the archive") + ": " + (appendErr.text.trim().split("\n").pop() || "");
        }
    }

    // into a new folder beside the archive, or inside `where` when one is given
    property bool probeThenExtract: false  // a size/space preflight is in flight
    property string probeWhere: ""        // where to extract once the preflight says yes
    property string probeKind: ""         // "extract" (whole archive) | "batch" (selected entries)
    property real probeSize: 0            // uncompressed size of the selected entries
    function extract(where) {
        if (root.file === "" || root.extracting || root.probeThenExtract || root.entries.length === 0)
            return;
        if (root.single) { extractSingle(where || root.file.substring(0, root.file.lastIndexOf("/")), ""); return; }
        root.error = "";
        root.extractedTo = "";
        root.batchSummary = "";
        root.probeKind = "extract";
        root.probeSize = root.totalSize;
        // Write nothing until the destination has been checked: free bytes
        // there, and the archive's own size, are compared with the expanded
        // size summed from the headers. A bomb (huge expanded size from a tiny
        // file) or a full disk is refused with words, not a half-filled disk.
        root.probeThenExtract = true;
        root.probeWhere = where || "";
        spaceProbe.command = ["sh", "-c", 'printf "%s %s\\n" "$(df -PB1 -- "$1" | tail -1 | awk "{print \\$4}")" "$(stat -c %s -- "$2" || echo 0)"',
                              "sh", where || root.file.substring(0, root.file.lastIndexOf("/")), root.file];
        spaceProbe.running = true;
    }
    Process {
        id: spaceProbe
        stdout: StdioCollector { id: probeOut }
        onExited: code => {
            if (!root.probeThenExtract) return;
            root.probeThenExtract = false;
            const nums = probeOut.text.trim().split(/\s+/);
            const free = parseInt(nums[0]) || 0;
            const arc = parseInt(nums[1]) || 0;
            const exp = root.probeKind === "batch" ? root.probeSize : root.totalSize;
            // totalSize is the cumulative expected size from the headers
            if (exp > free) {
                const why = Tr.t("Not enough free space to extract this archive");
                root.error = why;
                if (root.probeKind === "batch") root.batchRefused(why);
                return;
            }
            // a tiny archive claiming a huge expanded size is a decompression bomb
            if (arc > 0 && exp > arc * 100 && exp > 104857600) {
                const why = Tr.t("Refusing to extract: this archive looks like a decompression bomb");
                root.error = why;
                if (root.probeKind === "batch") root.batchRefused(why);
                return;
            }
            if (root.probeKind === "batch") { root.batchExtractNow(); return; }
            root.extractNow(root.probeWhere);
        }
    }
    function extractNow(where) {
        root.extracting = true;
        const parent = where || root.file.substring(0, root.file.lastIndexOf("/"));
        const stem = root.name.replace(/\.(tar\.(gz|xz|zst|bz2|lz4|lzma)|tgz|txz|tbz2|[A-Za-z0-9]+)$/, "") || "archive";
        // the hardened reader takes back anything it wrote on a wrong password
        extractor.payload = root.pass + "\n";
        // "rename" keeps today's never-overwrite behaviour (the default);
        // "overwrite" is an explicit choice to replace the named folder, and
        // "skip" refuses instead of writing beside an existing folder. The
        // hardened reader still validates every entry inside the temp dir.
        extractor.command = ["sh", "-c", 'd="$1/$2"
case "$5" in
  overwrite) rm -rf -- "$d" ;;
  skip) if [ -e "$d" ]; then printf "Destination already exists\\n" >&2; exit 3; fi ;;
  *) n=2; while [ -e "$d" ]; do d="$1/$2 ($n)"; n=$((n+1)); done ;;
esac
exec python3 "$3" extract "$4" "$d"',
                             "sh", parent, stem, root.extractTool, root.file, root.overwritePolicy];
        extractor.stdinEnabled = true;
        extractor.running = true;
    }
    Process {
        id: extractor
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload); payload = ""; stdinEnabled = false; }
        stdout: StdioCollector { id: madeDir }
        stderr: StdioCollector { id: extractErr }
        onExited: code => {
            root.extracting = false;
            let result = {};
            try { result = JSON.parse(madeDir.text.trim()) || {}; } catch (e) {}
            if (root.askResult(result, extractErr.text, "extract"))
                return;
            if (code === 0 && result.saved) root.extractedTo = result.saved;
            else root.error = Tr.t("Could not extract") + ": " + (result.error || extractErr.text.trim().split("\n").pop() || root.name);
        }
    }

    // ---- integrity: read every entry's bytes, write nothing ----------------
    // File Roller and Ark both offer "Test archive". libarchive verifies the
    // checksums as it streams each member; sending that stream to /dev/null
    // proves the content can be read without writing a single file.
    function testArchive() {
        if (root.file === "" || root.testing || root.entries.length === 0)
            return;
        root.error = "";
        root.testResult = "";
        root.testing = true;
        tester.command = ["sh", "-c", 'exec bsdtar --passphrase "$1" -xOf "$2" > /dev/null',
                          "sh", root.pass, root.file];
        tester.running = true;
    }
    Process {
        id: tester
        stderr: StdioCollector { id: testErr }
        onExited: code => {
            root.testing = false;
            if (code === 0) { root.testResult = Tr.t("Done testing %1").arg(root.name); return; }
            if (root.askPassword(testErr.text, "test")) return;
            root.error = testErr.text.trim().split("\n").pop()
                || Tr.t("Not an archive that can be read") + ": " + root.name;
        }
    }

    function human(bytes) { return Format.humanSize(bytes, "si"); }
}
