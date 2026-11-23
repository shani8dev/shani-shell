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
    property string extractedTo: ""       // the folder the last extraction made
    property string passphrase: ""        // what a person typed for a protected archive
    property bool needsPassword: false    // bsdtar said the passphrase is wrong (or none was given)
    property string retry: ""             // what to do again once the password is given: "list" | "extract" | "one:<path>"
    property string made: ""              // the archive the last Compress made
    property bool creating: false
    // never empty: bsdtar would ask on a terminal it does not have, forever
    readonly property string pass: passphrase || "\u0001no-password"
    readonly property bool available: tool.found
    readonly property string extractTool: Quickshell.env("SHANI_ARCHIVE_EXTRACT_TOOL") || "/usr/lib/shani-shell/zipcrypt.py"
    property bool single: false           // a lone compressed file, not an archive (bsdcat takes it out)
    readonly property var singleExts: ["gz", "bz2", "xz", "zst", "lz", "lzma", "lz4", "Z"]
    readonly property string singleExt: { const m = /\.([A-Za-z0-9]+)$/.exec(name); return m && singleExts.indexOf(m[1]) >= 0 ? m[1] : ""; }
    readonly property var types: ["zip", "tar", "gz", "tgz", "xz", "txz", "zst", "bz2", "tbz2", "7z", "iso", "rar", "cpio", "jar", "apk", "deb", "rpm", "cab", "lz4", "lzma"]

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
        root.entries = [];
        root.totalSize = 0;
        root.error = "";
        root.extractedTo = "";
        root.passphrase = "";
        root.needsPassword = false;
        root.single = false;
        root.toCompress = [];
        list();
    }
    function list() {
        root.reading = true;
        lister.command = ["bsdtar", "--passphrase", root.pass, "-tvf", root.file];
        lister.running = true;
    }
    // a window can go away while a job is still running; stop it here, not in
    // the UI, so closing is the same as cancelling for every caller
    function cancel() {
        if (lister.running) lister.running = false;
        if (singleSize.running) singleSize.running = false;
        if (singleOut.running) singleOut.running = false;
        if (hardOne.running) hardOne.running = false;
        if (extractor.running) extractor.running = false;
        if (maker.running) maker.running = false;
        if (appender.running) appender.running = false;
        root.reading = false;
        root.extracting = false;
        root.creating = false;
        root.appending = false;
        root.extractWhenRead = false;
    }
    function close() {
        cancel();
        shown = false;
        passphrase = "";
        needsPassword = false;
        retry = "";
        newPass = "";
    }

    Process {
        id: tool
        property bool found: false
        running: true
        command: ["sh", "-c", "command -v bsdtar"]
        onExited: code => found = code === 0
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
            root.reading = false;
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
            } else if (root.extractWhenRead) {
                root.extractWhenRead = false;
                root.extract("");
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
        root.retry = what;
        return true;
    }
    // the hardened extractor reports a wrong password in its JSON; bsdtar's
    // wording is kept as a fallback for the paths that still use it
    function askResult(result, stderr, what) {
        if (result && result.wrongPassword) {
            root.error = root.passphrase ? Tr.t("That password is not right") : "";
            root.needsPassword = true;
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
        entries = [];
        totalSize = 0;
        extractedTo = "";
        needsPassword = false;
        made = "";
        error = "";
        newPass = "";
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
            if (code === 0) root.made = madeOut.text;
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
    property string zipTool: Quickshell.env("SHANI_ZIPADD_TOOL") || "/usr/lib/shani-shell/zipadd.py"

    function append(paths) {
        const list = (typeof paths === "string" ? [paths] : Array.from(paths || []).map(String)).filter(p => p);
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
                root.list();
            } else
                root.error = Tr.t("Could not add to the archive") + ": " + (appendErr.text.trim().split("\n").pop() || "");
        }
    }

    // into a new folder beside the archive, or inside `where` when one is given
    function extract(where) {
        if (root.file === "" || root.extracting || root.entries.length === 0)
            return;
        if (root.single) { extractSingle(where || root.file.substring(0, root.file.lastIndexOf("/")), ""); return; }
        root.error = "";
        root.extractedTo = "";
        root.extracting = true;
        const parent = where || root.file.substring(0, root.file.lastIndexOf("/"));
        const stem = root.name.replace(/\.(tar\.(gz|xz|zst|bz2|lz4|lzma)|tgz|txz|tbz2|[A-Za-z0-9]+)$/, "") || "archive";
        // the hardened reader takes back anything it wrote on a wrong password
        extractor.payload = root.pass + "\n";
        extractor.command = ["sh", "-c", 'd="$1/$2"; n=2; while [ -e "$d" ]; do d="$1/$2 ($n)"; n=$((n+1)); done; exec python3 "$3" extract "$4" "$d"',
                             "sh", parent, stem, root.extractTool, root.file];
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

    function human(bytes) {
        const units = ["B", "kB", "MB", "GB", "TB"];
        let v = bytes, i = 0;
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        return (i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)) + " " + units[i];
    }
}
