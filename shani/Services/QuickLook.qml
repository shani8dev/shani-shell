pragma Singleton
// Quick Look: a file seen without opening an app (Space in Files, Ctrl+Y on a
// launcher file, `shani quick-look PATH`), as macOS's Quick Look and GNOME's
// Sushi do. What it is decides what is shown: a picture, a video or a song
// (playing), a PDF's first page (poppler, as Document Viewer renders), the
// start of a text file in the editor's colours, an archive's list, a folder's
// first entries, or for anything else its icon, size and date. Left and Right
// walk the files beside it (the list the caller gave).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/FileIcons.js" as FileIcons

Singleton {
    id: root
    property bool shown: false
    property string path: ""
    property var list: []               // the files Left/Right walk, in the caller's order
    property string kind: ""            // image | video | audio | pdf | text | archive | folder | other
    property string text: ""            // a text file's start, an archive's or folder's listing
    property string page: ""            // a PDF's first page, rendered
    property real size: -1
    property string modified: ""
    property string error: ""

    readonly property string name: path.split("/").pop()
    readonly property var exts: ({
        image: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "tif", "tiff", "ico"],
        video: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "ogv", "mpg", "mpeg", "wmv"],
        audio: ["mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav"],
        pdf: ["pdf"],
        archive: ["zip", "tar", "gz", "tgz", "xz", "txz", "bz2", "tbz2", "zst", "7z", "iso", "rar", "cpio", "jar"],
        text: ["txt", "md", "markdown", "rst", "log", "csv", "tsv", "json", "xml", "yaml", "yml", "toml", "ini", "conf", "cfg",
               "sh", "bash", "zsh", "fish", "py", "js", "ts", "qml", "c", "h", "cpp", "hpp", "rs", "go", "java", "kt", "rb",
               "php", "lua", "css", "html", "htm", "sql", "kdl", "nix", "diff", "patch", "desktop", "service", "srt", "vtt"]
    })
    function kindOf(p, isDir) {
        if (isDir)
            return "folder";
        const ext = p.indexOf(".") > 0 ? p.split(".").pop().toLowerCase() : "";
        for (const k of Object.keys(exts))
            if (exts[k].indexOf(ext) >= 0)
                return k;
        // no extension: a README, a Makefile, a script - shown as text when it is text
        return ext === "" ? "maybe-text" : "other";
    }

    function open(p, siblings) {
        if (!p)
            return;
        list = (siblings && siblings.length) ? siblings : [p];
        show(p);
    }
    function show(p) {
        path = p;
        text = "";
        page = "";
        error = "";
        size = -1;
        modified = "";
        kind = "";
        shown = true;
        probe.running = false;
        probe.running = true;
    }
    function step(d) {
        const i = list.indexOf(path);
        if (i < 0 || list.length < 2)
            return;
        show(list[(i + d + list.length) % list.length]);
    }
    function close() { shown = false; reader.running = false; }
    function openIt() { Quickshell.execDetached(["gio", "open", path]); close(); }

    function humanSize(b) {
        if (b < 0) return "";
        const u = ["B", "kB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
        return (i ? b.toFixed(b < 10 ? 1 : 0) : b) + " " + u[i];
    }
    function icon() {
        const ext = name.indexOf(".") > 0 ? "." + name.split(".").pop().toLowerCase() : "";
        return FileIcons.iconFor({ isDir: kind === "folder", ext: ext, image: kind === "image" });
    }

    // what it is: a folder or a file, its size and date
    Process {
        id: probe
        command: ["stat", "-L", "-c", "%F\t%s\t%Y", root.path]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\t");
                if (f.length < 3) {
                    root.error = Tr.t("It is not there any more");
                    root.kind = "other";
                    return;
                }
                root.size = f[0] === "directory" ? -1 : Number(f[1]);
                root.modified = Qt.formatDateTime(new Date(Number(f[2]) * 1000), "d MMM yyyy, hh:mm");
                let k = root.kindOf(root.path, f[0] === "directory");
                if (k === "maybe-text")
                    k = Number(f[1]) < 2000000 ? "text" : "other";
                root.kind = k;
                root.load();
            }
        }
    }
    function load() {
        let cmd = null;
        if (kind === "text")
            // the start of it: enough to see what it is, never a whole log; binary refused
            cmd = ['f=$1; if LC_ALL=C grep -qI . "$f" 2>/dev/null || [ ! -s "$f" ]; then head -c 65536 "$f"; else exit 3; fi', path];
        else if (kind === "archive")
            cmd = ['bsdtar -tf "$1" 2>/dev/null | head -n 400; exit ${PIPESTATUS:-0}', path];
        else if (kind === "folder")
            cmd = ['ls -1Ap --group-directories-first -- "$1" | head -n 400', path];
        else if (kind === "pdf")
            cmd = ['d=${XDG_CACHE_HOME:-$HOME/.cache}/shani-shell/quicklook; mkdir -p "$d"; o="$d/$(printf %s "$1" | md5sum | cut -c1-16)"; [ -f "$o.png" ] || pdftoppm -png -r 90 -f 1 -l 1 -singlefile -- "$1" "$o" || exit 3; echo "$o.png"', path];
        if (!cmd)
            return;
        reader.target = path;
        reader.command = ["bash", "-c"].concat([cmd[0], "sh", cmd[1]]);
        reader.running = false;
        reader.running = true;
    }
    Process {
        id: reader
        property string target: ""
        stdout: StdioCollector { id: readOut }
        onExited: code => {
            if (reader.target !== root.path)
                return;
            if (root.kind === "pdf") {
                if (code === 0) root.page = readOut.text.trim();
                else root.error = Tr.t("This PDF could not be shown");
            } else if (code === 3 && root.kind === "text") {
                root.kind = "other";            // not text after all
            } else {
                root.text = readOut.text;
                if (root.kind === "archive" && root.text.trim() === "")
                    root.error = Tr.t("Nothing could be read from this archive");
            }
        }
    }
}
