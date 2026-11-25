pragma Singleton
// PDF Signer: sign a PDF, or fill a field on it.
// The current page is rendered by the existing PdfViewer (poppler
// pdftoppm PNGs in ~/.cache/shani-pdf). The stored signature image
// (~/Documents/Signature.png by default, chosen with "Choose signature")
// is placed at x/y with a scale; typed fill text is placed at textX/textY.
// "Save signed copy" renders the page fresh via pdftoppm at 150 dpi,
// composites the signature (and the text, when there is any) onto it with
// ImageMagick `convert` at those offsets, then turns the result into a
// PDF — img2pdf when there is one, Ghostscript (`gs`) otherwise — named
// "* - signed <timestamp>.pdf" beside the original, so saving again never
// overwrites an earlier signed copy. The original is never touched.
// Shown by Modules/PdfSigner/PdfSignerPanel.qml until closed.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string file: ""               // the PDF being signed, while shown
    property string signature: defaultSignature()  // ~/Documents/Signature.png
    property int x: 100                    // signature placement, in rendered pixels
    property int y: 100
    property real scale: 1.0               // signature scale (1.0 == 100%)
    property string fillText: ""           // typed text to render onto the page
    property int textX: 100                // fill-text placement
    property int textY: 220
    property int textSize: 28              // fill-text point size
    property string pdfSignerFile: ""         // the last "* - signed.pdf" written
    property string lastSaved: ""          // same, for `state`
    property string error: ""
    property string status: ""
    property bool saving: false
    // ---- page range + stamps + password (the Pds/merge set) --------------------
    property string pageRange: ""            // "1-3,5": stamp only these pages; empty = every page
    property string rangeError: ""           // why pageRange is invalid, when it is
    property string stampText: ""            // stamped on stamped pages, with the date when stampDate
    property bool stampDate: false
    property bool stampPageNumber: false
    property string password: ""             // for "Protect with password"
    property string protectOut: ""           // the protected copy (defaults to file + " - protected.pdf")
    property string bookmarksOut: ""         // the exported bookmarks file (defaults next to the file)

    readonly property bool shown: Ui.pdfSigner
    readonly property string name: file === "" ? "" : file.split("/").pop()
    readonly property string pdfSignerPath: pdfSignerPathFor(file)
    readonly property string pageLabel: PdfViewer.label

    function defaultSignature() { return (Quickshell.env("HOME") || "/tmp") + "/Documents/Signature.png"; }
    // the signed copy goes beside the original with a timestamp so a second
    // save never destroys the first: "doc.pdf" -> "doc - signed 20261123-143022-456.pdf"
    function pdfSignerPathFor(pdf) {
        if (!pdf)
            return "";
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss-zzz");
        return /\.pdf$/i.test(pdf)
            ? pdf.replace(/\.pdf$/i, " - signed " + stamp + ".pdf")
            : pdf + " - signed " + stamp + ".pdf";
    }

    // ---- open: an argument, a folder's last PDF, or what PdfViewer has -----
    // "arg or folder last": a PDF path opens at once; a folder opens its
    // most recently modified PDF (the folder's last); no argument reuses
    // the PDF the reader already has open, or the last PDF in ~/Documents.
    function open(pdf) {
        Ui.closeAll();
        Ui.pdfSigner = true;
        error = "";
        status = "";
        let target = String(pdf || "").trim();
        if (!target) {
            if (PdfViewer.file) {
                doOpen(PdfViewer.file);
                return;
            }
            target = (Quickshell.env("HOME") || "/tmp") + "/Documents";
        }
        // a directory (or no argument at all) resolves to its last PDF,
        // asynchronously; a plain file opens at once
        if (/\.pdf$/i.test(target)) {
            doOpen(target);
        } else {
            resolveProc.command = ["sh", "-c",
                'd="$1"; [ -d "$d" ] || exit 0; ls -t "$d"/*.pdf "$d"/*.PDF 2>/dev/null | head -1', "sh", target];
            resolveProc.running = true;
        }
    }
    function doOpen(pdf) {
        file = pdf;
        signature = signature || defaultSignature();
        PdfViewer.open(pdf);
    }
    Process {
        id: resolveProc
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.trim().split("\n").filter(s => s)[0] || "";
                if (found)
                    root.doOpen(found);
                else
                    root.error = Tr.t("No PDF found there");
            }
        }
        onExited: code => { if (code !== 0 && root.file === "") root.error = Tr.t("No PDF found there"); }
    }

    function close() { Ui.pdfSigner = false; }
    function toggle(pdf) { root.shown ? close() : open(pdf || file); }

    // ---- placement ----------------------------------------------------------
    function setSignature(path) { if (path) { signature = path; error = ""; } }
    function chooseSignature(path) { setSignature(path); }
    function setPosition(px, py) { x = parseInt(px) || 0; y = parseInt(py) || 0; }
    function setScale(s) { const v = parseFloat(s); if (isFinite(v) && v > 0) scale = Math.min(4, Math.max(0.1, v)); }
    function place(px, py, s) { setPosition(px, py); if (s !== undefined) setScale(s); }
    function setFillText(t) { fillText = String(t || ""); }
    function setText(text) { setFillText(text); }
    function setTextPosition(px, py) { textX = parseInt(px) || 0; textY = parseInt(py) || 0; }

    // ---- page range ----------------------------------------------------------
    function validPageRange(text, count) {
        const s = String(text === undefined || text === null ? "" : text).trim();
        if (s === "") return true;                    // empty range = every page
        if (!/^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$/.test(s)) return false;
        for (const part of s.split(",")) {
            const b = part.split("-").map(Number);
            const from = b[0], to = b.length > 1 ? b[1] : b[0];
            if (from < 1 || to > count || from > to) return false;
        }
        return true;
    }
    // the pages in the range, sorted and unique, 1-based ([] = every page)
    function pagesIn(text) {
        const out = [], seen = {};
        const n = Math.max(1, PdfViewer.pages ? PdfViewer.pages.length : 1);
        const s = String(text || "").trim();
        if (!s)
            return out;
        for (const part of s.split(",")) {
            const m = String(part).trim().match(/^(\d+)(?:-(\d+))?$/);
            if (!m) continue;
            const from = +m[1], to = m[2] ? +m[2] : from;
            for (let p = from; p <= to; p++)
                if (p >= 1 && p <= n && !seen[p]) { seen[p] = 1; out.push(p); }
        }
        return out.sort((a, b) => a - b);
    }
    function setPageRange(text) {
        const s = String(text || "").trim();
        const ok = validPageRange(s, Math.max(1, PdfViewer.pages ? PdfViewer.pages.length : 1));
        rangeError = s !== "" && !ok ? Tr.t("Invalid page range — use 1-3,5") : "";
        pageRange = s;
    }
    function setPassword(p) { password = String(p || ""); }
    function setStampText(t) { stampText = String(t || ""); }

    // ---- password protect ----------------------------------------------------
    function protect() {
        if (!file) { error = Tr.t("Open a PDF first"); return; }
        if (!password) { error = Tr.t("Set a password first"); return; }
        if (protectOut === "")
            protectOut = file + " - protected.pdf";
        // pdftk: encrypt in.pdf to out with the same user/owner password
        protectProc.command = ["sh", "-c",
            'pdftk "$1" output "$2" encrypt "$3" "$3" 2>&1 || exit 1',
            "sh", file, protectOut, password];
        protectProc.running = true;
    }

    // ---- bookmarks export / import -------------------------------------------
    function exportBookmarks(out) {
        const target = out || bookmarksOut || (file + ".bookmarks.json");
        const bm = (PdfViewer.userBookmarks || []).map(b => ({ page: b.page || 0, title: b.title || "" }));
        if (!bm.length) { error = Tr.t("No bookmarks on this document"); return; }
        // one JSON object per line: page, then tab, then the title
        bmWrite.command = ["sh", "-c", 'printf "%s\\n" "${@:2}" > "$1"', "sh", target]
            .concat(bm.map(b => JSON.stringify(b)));
        bmWrite.running = true;
    }
    function importBookmarks(from) {
        if (!from) { error = Tr.t("Pick a bookmarks file"); return; }
        bmRead.command = ["sh", "-c",
            'python3 -c \'import json,sys\nfor line in open(sys.argv[1]):\n    line=line.strip()\n    if line:\n        d=json.loads(line)\n        print(str(d.get("page",0)) + chr(9) + d.get("title",""))\' "$1"',
            "sh", from];
        bmRead.running = true;
    }

    // ---- PAdES signatures review ----------------------------------------------
    function signatures() {
        if (!file) { error = Tr.t("Open a PDF first"); return; }
        sigProc.command = ["sh", "-c", 'pdfsig "$1" 2>&1 || true', "sh", file];
        sigProc.running = true;
    }

    // ---- save a signed copy -------------------------------------------------
    // pdftoppm renders every page, `convert` composites the signature at
    // +x+y (resized by scale), annotates the fill text at +textX+textY and
    // adds the stamps, then img2pdf / Ghostscript makes the PDF. Only the
    // pages in pageRange (all pages when it is empty) are stamped. The
    // output is a fresh timestamped "* - signed ….pdf" beside the original,
    // so an earlier signed copy is never overwritten.
    function save() {
        if (!file || saving)
            return;
        if (!signature && !fillText) {
            error = Tr.t("Choose a signature first");
            return;
        }
        if (rangeError) {
            error = rangeError;
            return;
        }
        error = "";
        status = Tr.t("Saving signed copy…");
        saving = true;
        const out = pdfSignerPathFor(file);
        const page = Math.max(1, (PdfViewer.page || 0) + 1);
        const pct = Math.round((scale || 1) * 100);
        const range = pagesIn(pageRange);            // [] = every page
        // convert composites only what is there: no signature file, no
        // signature layer; no fill text, no text layer. Quoting is done
        // through "$N" argv slots, never by interpolation, so a path or
        // typed text with spaces or quotes cannot break the command.
        // Render EVERY page: `-f N -singlefile` produced a one-page "signed
        // copy" and destroyed the rest of the document (real data loss).
        const script = [
            'set -e',
            'RANGE="${12}"; STAMPTEXT="${13}"; STAMPTIME="${14}"; STAMPPN="${15}"',
            'work=$(mktemp -d)',
            'trap \'rm -rf "$work"\' EXIT',
            'pdftoppm -png -r 150 "$1" "$work/page"',
            'mapfile -t pages < <(find "$work" -maxdepth 1 -name "page-*.png" | sort -V)',
            // 1-based page in the range, given as $RANGE ("1,3" or "" = every page)
            'in_range() {',
            '    local p',
            '    [ -z "$RANGE" ] && return 0',
            '    for p in ${RANGE//,/ }; do [ "$p" = "$1" ] && return 0; done',
            '    return 1',
            '}',
            // stamp_one: $1 png, $2 page number, $3 sig, $4 x, $5 pct, $6 y,
            // $7 fill text, $8 tx, $9 ty, $10 size
            'stamp_one() {',
            '    local f="$1"',
            '    if [ -n "$3" ] && [ -f "$3" ]; then',
            '        convert "$3" -resize "$5%" "$work/sig.png"',
            '        convert "$f" "$work/sig.png" -geometry "+$4+$6" -composite "$work/s.png"; mv "$work/s.png" "$f"',
            '    fi',
            '    if [ -n "$7" ]; then',
            '        convert "$f" -gravity NorthWest -pointsize "$10" -fill black -annotate "+$8+$9" "$7" "$work/s.png"; mv "$work/s.png" "$f"',
            '    fi',
            '    if [ -n "$STAMPTEXT" ]; then',
            '        convert "$f" -gravity SouthEast -fill black -pointsize 13 -annotate 0+0 "$STAMPTEXT ($(date +%F))" "$work/s.png"; mv "$work/s.png" "$f"',
            '    fi',
            '    if [ "$STAMPTIME" = "1" ]; then',
            '        convert "$f" -gravity SouthEast -fill black -pointsize 13 -annotate 0-15 "$(date +%T)" "$work/s.png"; mv "$work/s.png" "$f"',
            '    fi',
            '    if [ "$STAMPPN" = "1" ]; then',
            '        convert "$f" -gravity SouthEast -fill black -pointsize 13 -annotate 0-30 "Page $2" "$work/s.png"; mv "$work/s.png" "$f"',
            '    fi',
            '}',
            'i=0',
            'for f in "${pages[@]}"; do',
            '    i=$((i+1))',
            '    if in_range "$i"; then stamp_one "$f" "$i" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}"; fi',
            'done',
            'i=0; parts=()',
            'for p in "${pages[@]}"; do',
            '  i=$((i+1))',
            '  if command -v img2pdf >/dev/null 2>&1; then',
            '    img2pdf "$p" -o "$work/$i.pdf"',
            '  elif command -v gs >/dev/null 2>&1; then',
            '    gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$work/$i.pdf" "$p" 2>/dev/null || convert "$p" "$work/$i.pdf"',
            '  else',
            '    convert "$p" "$work/$i.pdf"',
            '  fi',
            '  parts+=("$work/$i.pdf")',
            'done',
            'if [ ${#parts[@]} -eq 1 ]; then',
            '  cp "${parts[0]}" "$11"',
            'else',
            '  pdfunite "${parts[@]}" "$11" || gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$11" "${parts[@]}" 2>/dev/null',
            'fi',
            'printf "%s\\n" "$11"'
        ].join("\n");
        saveProc.command = ["bash", "-c", script, "bash",
            file, String(page), signature || "", String(x), String(pct), String(y),
            fillText || "", String(textX), String(textY), String(textSize), out,
            range.join(","), stampText || "", stampDate ? "1" : "", stampPageNumber ? "1" : ""];
        saveProc.out = out;
        saveProc.running = true;
    }
    function saveSignedCopy() { save(); }

    Process {
        id: saveProc
        property string out: ""
        stdout: SplitParser { onRead: l => { if (l.trim()) root.pdfSignerFile = l.trim(); } }
        onExited: code => {
            root.saving = false;
            if (code === 0) {
                root.lastSaved = root.pdfSignerFile || root.out;
                root.status = Tr.t("Saved: ") + root.lastSaved;
                root.error = "";
                Quickshell.execDetached(["notify-send", "-a", "Signed", Tr.t("Signed copy saved"), root.lastSaved]);
            } else {
                root.error = Tr.t("Could not save the signed copy");
                root.status = "";
            }
        }
    }

    Process {
        id: protectProc
        stdout: SplitParser { onRead: l => { if (l.trim()) root.status = l.trim(); } }
        onExited: code => {
            if (code === 0) {
                root.status = Tr.t("Protected copy written: ") + root.protectOut;
            } else {
                root.error = Tr.t("Password protection failed");
                root.status = "";
            }
        }
    }

    Process {
        id: bmWrite
        stdout: SplitParser { onRead: l => { if (l.trim()) root.status = l.trim(); } }
        onExited: code => { if (code !== 0) root.error = Tr.t("Could not write the bookmarks file"); }
    }

    Process {
        id: bmRead
        stdout: SplitParser { onRead: l => {
            const parts = l.split("\t");
            if (parts.length > 0)
                PdfViewer.addBookmark(parseInt(parts[0]) || 0, parts.slice(1).join("\t"));
        } }
        onExited: code => {
            root.status = code === 0 ? Tr.t("Bookmarks imported") : Tr.t("Could not read the bookmarks file");
            root.error = "";
        }
    }

    Process {
        id: sigProc
        stdout: SplitParser { onRead: l => { if (l.trim()) root.status = l.trim(); } }
        onExited: code => { if (code !== 0) root.status = Tr.t("pdfsig is not installed"); }
    }

    Component.onCompleted: { signature = defaultSignature(); }
}
