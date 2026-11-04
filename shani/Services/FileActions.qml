pragma Singleton
// What can be done with a file, without opening an app (after Tangerine's
// drag-and-convert): drop files on the Island - or "Convert…" on a Shelf item -
// and a card offers what fits them. Images to PNG/JPEG/WebP, half the size, a
// smaller file, location and camera data removed, their text read, several as
// one PDF; video to MP4/WebM, a GIF of the start, its sound as MP3, a smaller
// file; audio between MP3/OGG/FLAC/WAV; a PDF's pages as pictures or its text;
// anything zipped, shared or handed to Chronoa. The result goes beside the
// original, never over it, and a notification opens it. Tools: ImageMagick,
// ffmpeg, poppler, tesseract, bsdtar (libarchive) - an action whose tool is not
// installed is not offered.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var files: []               // what the card is about (Ui shows it while not empty)
    property var tools: ({})
    property string last: ""             // the last result, for the tests

    function kind(p) {
        const e = (p.split(".").pop() || "").toLowerCase();
        if (/^(png|jpe?g|webp|avif|gif|bmp|tiff?|heic|heif)$/.test(e)) return "image";
        if (/^(mp4|mkv|webm|mov|avi|m4v|flv|wmv)$/.test(e)) return "video";
        if (/^(mp3|ogg|oga|opus|flac|wav|m4a|aac|wma)$/.test(e)) return "audio";
        if (e === "pdf") return "pdf";
        return "other";
    }
    readonly property string kinds: {
        const k = [...new Set(files.map(f => kind(f)))];
        return k.length === 1 ? k[0] : "mixed";
    }
    // [{ id, label, icon }] for what the files are and the tools there are
    readonly property var actions: {
        const t = tools, k = kinds, a = [];
        const add = (id, label, icon, need) => { if (!need || t[need]) a.push({ id: id, label: label, icon: icon }); };
        if (k === "image") {
            add("png", Tr.t("Make it a PNG"), "image-x-generic", "magick");
            add("jpg", Tr.t("Make it a JPEG"), "image-x-generic", "magick");
            add("webp", Tr.t("Make it a WebP"), "image-x-generic", "magick");
            add("half", Tr.t("Half the size"), "zoom-out", "magick");
            add("smaller", Tr.t("A smaller file"), "package-x-generic", "magick");
            add("fit", Tr.t("Fit under a size limit (forms)"), "document-save", "magick");
            add("strip", Tr.t("Remove location and camera data"), "security-high", "magick");
            add("ocr", Tr.t("Read the text in it"), "edit-select-all", "tesseract");
            if (files.length > 1) add("pdf", Tr.t("Put them in one PDF"), "x-office-document", "magick");
        } else if (k === "video") {
            add("mp4", Tr.t("Make it an MP4"), "video-x-generic", "ffmpeg");
            add("webm", Tr.t("Make it a WebM"), "video-x-generic", "ffmpeg");
            add("gif", Tr.t("A GIF of the first 10 seconds"), "image-x-generic", "ffmpeg");
            add("mp3", Tr.t("Just the sound, as MP3"), "audio-x-generic", "ffmpeg");
            add("smaller", Tr.t("A smaller file"), "package-x-generic", "ffmpeg");
        } else if (k === "audio") {
            add("mp3", Tr.t("Make it an MP3"), "audio-x-generic", "ffmpeg");
            add("ogg", Tr.t("Make it an OGG"), "audio-x-generic", "ffmpeg");
            add("flac", Tr.t("Make it a FLAC"), "audio-x-generic", "ffmpeg");
            add("wav", Tr.t("Make it a WAV"), "audio-x-generic", "ffmpeg");
        } else if (k === "pdf") {
            add("fit", Tr.t("Fit under a size limit (forms)"), "document-save", "gs");
            add("pages", Tr.t("Its pages as pictures"), "image-x-generic", "pdftoppm");
            add("text", Tr.t("Its text"), "text-x-generic", "pdftotext");
        }
        add("zip", files.length > 1 ? Tr.t("Zip them together") : Tr.t("Zip it"), "package-x-generic", "bsdtar");
        add("share", Tr.t("Share…"), "emblem-shared", "");
        add("ask", Tr.t("Ask Chronoa about it"), "face-smile-big", "");
        return a;
    }

    function offer(paths) { files = paths.filter(p => p); fitting = false; }
    function close() { files = []; fitting = false; }

    // ---- fit a size limit (application forms). Portals ask a maximum and often
    // a minimum (a 2 KB photo is refused as much as a 300 KB one), sometimes
    // exact pixels (a passport-size photo 200x230, a signature 140x60). Images:
    // ImageMagick finds the best JPEG quality under the maximum (jpeg:extent)
    // and shrinks the picture only when even that is too big; below the
    // minimum it is saved at full quality. PDFs: Ghostscript at falling image
    // resolutions until it fits. The presets are the usual kinds of upload with
    // typical limits; forms differ, so any limit can be typed. The second step
    // of the card: `fitting`.
    property bool fitting: false
    readonly property var fitPresets: [
        { kinds: "image", label: Tr.t("Passport-size photo"), min: 20, max: 50, w: 200, h: 230 },
        { kinds: "image", label: Tr.t("Photo"), min: 10, max: 200 },
        { kinds: "image", label: Tr.t("Signature"), min: 10, max: 20, w: 140, h: 60 },
        { kinds: "pdf", label: Tr.t("Document"), min: 50, max: 300 },
        { kinds: "image pdf", label: Tr.t("Under 50 KB"), max: 50 }, { kinds: "image pdf", label: Tr.t("Under 100 KB"), max: 100 },
        { kinds: "image pdf", label: Tr.t("Under 200 KB"), max: 200 }, { kinds: "image pdf", label: Tr.t("Under 500 KB"), max: 500 },
        { kinds: "image pdf", label: Tr.t("Under 1 MB"), max: 1024 }, { kinds: "image pdf", label: Tr.t("Under 2 MB"), max: 2048 }
    ]
    readonly property var presetsHere: fitPresets.filter(p => p.kinds.split(" ").indexOf(kinds) >= 0)
    function kb(n) { return n >= 1024 && n % 1024 === 0 ? (n / 1024) + " MB" : n + " KB"; }
    // { max, min, w, h } in KB and pixels; min, w, h may be 0
    function fit(lim) {
        const fs = files;
        close();
        const src = fs[0], max = Math.round(lim.max || 0), min = Math.round(lim.min || 0);
        if (!src || max <= 0) return;
        const pdf = kind(src) === "pdf";
        job.out = src.replace(/\.[^./]+$/, "") + " (" + (min > 0 ? kb(min) + "-" : "under ") + kb(max)
            + (lim.w > 0 && lim.h > 0 ? ", " + lim.w + "x" + lim.h : "") + ")." + (pdf ? "pdf" : "jpg");
        const img = 'in="$2"; max="$3"; min="$4"; W="$5"; H="$6"; size() { stat -c%s "$1"; }
            if [ "$W" -gt 0 ] && [ "$H" -gt 0 ]; then geo=(-resize "${W}x${H}^" -gravity center -extent "${W}x${H}"); w=0; else geo=(); w=3000; fi
            enc() { if [ "$w" -gt 0 ]; then r=(-resize "${w}x${w}>"); else r=(); fi
                magick "$in" -auto-orient -strip "${geo[@]}" "${r[@]}" -sampling-factor 4:2:0 -define jpeg:extent=${max}KB "$1"; }
            enc "$1"
            while [ "$(size "$1")" -gt $((max*1024)) ] && [ "$w" -gt 120 ]; do w=$((w*3/4)); enc "$1"; done
            if [ "$min" -gt 0 ] && [ "$(size "$1")" -lt $((min*1024)) ]; then
                magick "$in" -auto-orient -strip "${geo[@]}" -sampling-factor 4:4:4 -quality 100 "$1"; fi
            s=$(size "$1"); [ "$s" -le $((max*1024)) ] && [ "$s" -ge $((min*1024)) ]';
        const pdfs = 'in="$2"; max="$3"; min="$4"; cp "$in" "$1"; [ "$(stat -c%s "$1")" -le $((max*1024)) ] && exit 0
            for r in 200 150 110 85 72 50 36; do
            gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dDownsampleColorImages=true -dDownsampleGrayImages=true -dDownsampleMonoImages=true \
               -dColorImageResolution=$r -dGrayImageResolution=$r -dMonoImageResolution=$((r*2)) -dColorImageDownsampleThreshold=1.0 -dGrayImageDownsampleThreshold=1.0 \
               -sOutputFile="$1" "$in" || exit 1
            [ "$(stat -c%s "$1")" -le $((max*1024)) ] && exit 0; done; exit 1';
        job.command = ["bash", "-c", 'o="$1"; shift; b="${o%.*}"; e="${o##*.}"; n=2; while [ -e "$o" ]; do o="$b $n.$e"; n=$((n+1)); done; printf "%s\n" "$o"; set -- "$o" "$@"; ' + (pdf ? pdfs : img),
            "bash", job.out, src, String(max), String(min), String(lim.w || 0), String(lim.h || 0)];
        job.running = true;
    }

    readonly property var scripts: ({
        png: ["png", 'magick "$2" "$1"'], jpg: ["jpg", 'magick "$2" -quality 90 "$1"'], webp: ["webp", 'magick "$2" -quality 85 "$1"'],
        half: ["", 'magick "$2" -resize 50% "$1"'], strip: ["", 'magick "$2" -strip "$1"'],
        ocr: ["txt", 'tesseract "$2" "${1%.txt}" >/dev/null 2>&1'],
        pdf: ["pdf", 'o="$1"; shift; magick "$@" "$o"'],
        mp4: ["mp4", 'ffmpeg -y -loglevel error -i "$2" -c:v libx264 -crf 23 -preset medium -c:a aac "$1"'],
        webm: ["webm", 'ffmpeg -y -loglevel error -i "$2" -c:v libvpx-vp9 -crf 33 -b:v 0 -c:a libopus "$1"'],
        gif: ["gif", 'ffmpeg -y -loglevel error -t 10 -i "$2" -vf "fps=12,scale=640:-1:flags=lanczos" "$1"'],
        mp3: ["mp3", 'ffmpeg -y -loglevel error -i "$2" -vn -q:a 2 "$1"'], ogg: ["ogg", 'ffmpeg -y -loglevel error -i "$2" -vn -c:a libvorbis -q:a 5 "$1"'],
        flac: ["flac", 'ffmpeg -y -loglevel error -i "$2" -vn "$1"'], wav: ["wav", 'ffmpeg -y -loglevel error -i "$2" -vn "$1"'],
        pages: ["", 'd="${1%.*}"; mkdir -p "$d" && pdftoppm -png -r 120 "$2" "$d/page"'],
        text: ["txt", 'pdftotext -layout "$2" "$1"'],
        zip: ["zip", 'o="$1"; shift; bsdtar -a -cf "$o" -C "$(dirname "$1")" $(for f in "$@"; do printf "%s\\n" "$(basename "$f")"; done)']
    })
    function smallerScript() {
        return kinds === "video" ? ["mp4", 'ffmpeg -y -loglevel error -i "$2" -c:v libx264 -crf 30 -preset slow -c:a aac -b:a 96k "$1"']
                                 : ["jpg", 'magick "$2" -resize "2560x2560>" -quality 75 "$1"'];
    }
    function run(id) {
        const fs = files;
        close();
        if (!fs.length) return;
        if (id === "fit") { files = fs; fitting = true; return; }
        if (id === "share") { Share.open(fs[0]); return; }
        if (id === "ask") { Chronoa.ask("Here are some files for context: " + fs.join(", ")); return; }
        const sc = id === "smaller" ? smallerScript() : scripts[id];
        if (!sc) return;
        const src = fs[0], ext = sc[0] || (src.split(".").pop());
        const many = id === "pdf" || id === "zip";
        const base = src.replace(/\.[^./]+$/, "") + (many && fs.length > 1 ? " and more" : "") + (id === "half" ? " (half)" : id === "smaller" ? " (smaller)" : id === "strip" ? " (clean)" : "");
        job.out = base + "." + ext;
        job.command = ["sh", "-c", 'o="$1"; shift; b="${o%.*}"; e="${o##*.}"; n=2; while [ -e "$o" ]; do o="$b $n.$e"; n=$((n+1)); done; printf "%s\\n" "$o"; set -- "$o" "$@"; ' + sc[1], "sh", job.out].concat(many ? fs : [src]);
        job.running = true;
    }
    Process {
        id: job
        property string out: ""
        stdout: SplitParser { onRead: l => job.out = l }
        onExited: code => {
            const ok = code === 0;
            root.last = ok ? job.out : "";
            Quickshell.execDetached(["notify-send", "-a", "Files", "-i", ok ? "emblem-ok" : "dialog-error",
                ok ? Tr.t("Done") : Tr.t("That did not work"), ok ? job.out.replace(Quickshell.env("HOME"), "~") : job.out]);
        }
    }
    Process {
        running: true
        command: ["sh", "-c", 'for t in magick ffmpeg pdftoppm pdftotext tesseract bsdtar gs; do command -v $t >/dev/null && echo $t; done']
        stdout: StdioCollector { onStreamFinished: { const m = {}; for (const t of text.trim().split("\n")) if (t) m[t] = true; root.tools = m; } }
    }
}
