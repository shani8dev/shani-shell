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
// Extracting never writes over anything: the files go into a new folder
// named after the archive ("photos.zip" -> "photos", or "photos (2)" when
// that is taken). bsdtar refuses paths that climb out with ".." and absolute
// ones by itself, so an archive cannot place a file outside that folder.
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
        root.toCompress = [];
        list();
    }
    function list() {
        root.reading = true;
        lister.command = ["bsdtar", "--passphrase", root.pass, "-tvf", root.file];
        lister.running = true;
    }
    function close() { shown = false; }

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
                    const dir = m[1].charAt(0) === "d";
                    let path = m[3];
                    const link = path.indexOf(" -> ");
                    if (m[1].charAt(0) === "l" && link > 0)
                        path = path.substring(0, link);
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
                root.error = Tr.t("Not an archive that can be read") + ": " + root.name;
            } else if (root.extractWhenRead) {
                root.extractWhenRead = false;
                root.extract("");
            }
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
    function unlock(pw) {
        root.passphrase = pw;
        root.needsPassword = false;
        root.error = "";
        if (root.retry === "list") list();
        else if (root.retry === "extract") extract("");
        else if (root.retry.indexOf("one:") === 0) extractOne(root.retry.slice(4));
    }

    // one item (a file or a folder) beside the archive, under a name not taken
    function extractOne(entry) {
        if (root.file === "" || root.extracting || !entry)
            return;
        root.error = "";
        root.extractedTo = "";
        root.extracting = true;
        oneOut.target = entry;
        oneOut.command = ["sh", "-c", 'p=$1; t=$(mktemp -d "$p/.shani-extract.XXXXXX") || exit 1
            bsdtar --passphrase "$4" -xf "$2" -C "$t" -- "$3" || { s=$?; rm -rf "$t"; exit $s; }
            n=${3##*/}; case "$n" in *.*) b=${n%.*}; e=.${n##*.};; *) b=$n; e=;; esac
            d="$p/$n"; i=2; while [ -e "$d" ]; do d="$p/$b ($i)$e"; i=$((i+1)); done
            mv -- "$t/$3" "$d" && rm -rf "$t" && printf "%s" "$d"',
            "sh", root.file.substring(0, root.file.lastIndexOf("/")), root.file, entry, root.pass];
        oneOut.running = true;
    }
    Process {
        id: oneOut
        property string target: ""
        stdout: StdioCollector { id: oneMade }
        stderr: StdioCollector { id: oneErr }
        onExited: code => {
            root.extracting = false;
            if (code === 0) root.extractedTo = oneMade.text;
            else if (!root.askPassword(oneErr.text, "one:" + oneOut.target))
                root.error = Tr.t("Could not extract") + ": " + (oneErr.text.trim().split("\n").pop() || oneOut.target);
        }
    }

    // Compress: the chosen files into one archive beside them, under a free name
    property bool extractWhenRead: false  // Files' "Extract here": as soon as the list is in
    function extractHere(path) { open(path); extractWhenRead = true; }
    property var toCompress: []           // what Files asked to compress (the window shows the choices)
    property string format: "zip"
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
        shown = true;
    }
    function defaultName(paths) {
        return !paths || !paths.length ? "" : paths.length === 1 ? paths[0].split("/").pop().replace(/\.[^.\/]+$/, "") : Tr.t("Archive");
    }
    readonly property var formats: [{ ext: "zip", label: "ZIP" }, { ext: "tar.gz", label: "tar.gz" }, { ext: "tar.xz", label: "tar.xz" }, { ext: "7z", label: "7z" }]
    function create(given, ext, name) {
        // a list, however it came (a JS array, a QML list, one path)
        const paths = typeof given === "string" ? [given] : Array.from(given || []).map(String);
        if (!paths.length || root.creating)
            return;
        const parent = paths[0].substring(0, paths[0].lastIndexOf("/")) || "/";
        const stem = (name || defaultName(paths)).replace(/\//g, "-");
        root.error = "";
        root.made = "";
        root.creating = true;
        maker.command = ["sh", "-c", 'p=$1; s=$2; x=$3; shift 3
            t=$(mktemp -d "$p/.shani-archive.XXXXXX") || exit 1
            ( cd "$p" && bsdtar -acf "$t/$s.$x" -- "$@" ) || { r=$?; rm -rf "$t"; exit $r; }
            d="$p/$s.$x"; i=2; while [ -e "$d" ]; do d="$p/$s ($i).$x"; i=$((i+1)); done
            mv -- "$t/$s.$x" "$d" && rm -rf "$t" && printf "%s" "$d"',
            "sh", parent, stem, ext || "zip"].concat(paths.map(p => p.split("/").pop()));
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

    // into a new folder beside the archive, or inside `where` when one is given
    function extract(where) {
        if (root.file === "" || root.extracting || root.entries.length === 0)
            return;
        root.error = "";
        root.extractedTo = "";
        root.extracting = true;
        const parent = where || root.file.substring(0, root.file.lastIndexOf("/"));
        const stem = root.name.replace(/\.(tar\.(gz|xz|zst|bz2|lz4|lzma)|tgz|txz|tbz2|[A-Za-z0-9]+)$/, "") || "archive";
        // a password asked for halfway leaves no half-made folder behind
        extractor.command = ["sh", "-c", 'd="$1/$2"; n=2; while [ -e "$d" ]; do d="$1/$2 ($n)"; n=$((n+1)); done; mkdir -p -- "$d" && { bsdtar --passphrase "$4" -xf "$3" -C "$d" || { s=$?; rm -rf -- "$d"; exit $s; }; } && printf "%s" "$d"',
                             "sh", parent, stem, root.file, root.pass];
        extractor.running = true;
    }
    Process {
        id: extractor
        stdout: StdioCollector { id: madeDir }
        stderr: StdioCollector { id: extractErr }
        onExited: code => {
            root.extracting = false;
            if (code === 0)
                root.extractedTo = madeDir.text;
            else if (!root.askPassword(extractErr.text, "extract"))
                root.error = Tr.t("Could not extract") + ": " + (extractErr.text.trim().split("\n").pop() || root.name);
        }
    }

    function human(bytes) {
        const units = ["B", "kB", "MB", "GB", "TB"];
        let v = bytes, i = 0;
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        return (i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)) + " " + units[i];
    }
}
