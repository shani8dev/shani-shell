pragma Singleton
// Archives (Modules/Archives shows it): what is inside a zip, a tar (gz, xz,
// zst, bz2), a 7z or an ISO, and taking it out. libarchive's bsdtar does the
// reading, so every format it knows is known here.
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
        root.reading = true;
        lister.command = ["bsdtar", "-tvf", path];
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
            if (code !== 0)
                root.error = /passphrase|encrypt/i.test(listErr.text) ? Tr.t("This archive has a password, which is not supported here")
                    : Tr.t("Not an archive that can be read") + ": " + root.name;
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
        extractor.command = ["sh", "-c", 'd="$1/$2"; n=2; while [ -e "$d" ]; do d="$1/$2 ($n)"; n=$((n+1)); done; mkdir -p -- "$d" && bsdtar -xf "$3" -C "$d" && printf "%s" "$d"',
                             "sh", parent, stem, root.file];
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
            else
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
