pragma Singleton
// Signed (Omarchy Signed parity): sign a PDF, or fill a field on it.
// The current page is rendered by the existing PdfViewer (poppler
// pdftoppm PNGs in ~/.cache/shani-pdf). The stored signature image
// (~/Documents/Signature.png by default, chosen with "Choose signature")
// is placed at x/y with a scale; typed fill text is placed at textX/textY.
// "Save signed copy" renders the page fresh via pdftoppm at 150 dpi,
// composites the signature (and the text, when there is any) onto it with
// ImageMagick `convert` at those offsets, then turns the result into a
// PDF — img2pdf when there is one, Ghostscript (`gs`) otherwise — named
// "* - signed.pdf" beside the original. The original is never touched.
// Shown by Modules/Signed/SignedPanel.qml until closed.
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
    property string signedFile: ""         // the last "* - signed.pdf" written
    property string lastSaved: ""          // same, for `state`
    property string error: ""
    property string status: ""
    property bool saving: false

    readonly property bool shown: Ui.signed
    readonly property string name: file === "" ? "" : file.split("/").pop()
    readonly property string signedPath: signedPathFor(file)
    readonly property string pageLabel: PdfViewer.label

    function defaultSignature() { return (Quickshell.env("HOME") || "/tmp") + "/Documents/Signature.png"; }
    // the signed copy goes beside the original: "doc.pdf" -> "doc - signed.pdf"
    function signedPathFor(pdf) {
        if (!pdf)
            return "";
        return /\.pdf$/i.test(pdf) ? pdf.replace(/\.pdf$/i, " - signed.pdf") : pdf + " - signed.pdf";
    }

    // ---- open: an argument, a folder's last PDF, or what PdfViewer has -----
    // "arg or folder last": a PDF path opens at once; a folder opens its
    // most recently modified PDF (the folder's last); no argument reuses
    // the PDF the reader already has open, or the last PDF in ~/Documents.
    function open(pdf) {
        Ui.closeAll();
        Ui.signed = true;
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

    function close() { Ui.signed = false; }
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

    // ---- save a signed copy -------------------------------------------------
    // pdftoppm renders the current page (PdfViewer.page), `convert`
    // composites the signature at +x+y (resized by scale) and annotates
    // the fill text at +textX+textY, then img2pdf / Ghostscript makes
    // the PDF. The output is beside the original: "* - signed.pdf".
    function save() {
        if (!file || saving)
            return;
        if (!signature && !fillText) {
            error = Tr.t("Choose a signature first");
            return;
        }
        error = "";
        status = Tr.t("Saving signed copy…");
        saving = true;
        const out = signedPathFor(file);
        const page = Math.max(1, (PdfViewer.page || 0) + 1);
        const pct = Math.round((scale || 1) * 100);
        // convert composites only what is there: no signature file, no
        // signature layer; no fill text, no text layer. Quoting is done
        // through "$N" argv slots, never by interpolation, so a path or
        // typed text with spaces or quotes cannot break the command.
        const script = [
            'set -e',
            'work=$(mktemp -d)',
            'trap \'rm -rf "$work"\' EXIT',
            'pdftoppm -png -r 150 -f "$2" -singlefile "$1" "$work/page"',
            'if [ -n "$3" ] && [ -f "$3" ]; then',
            '  convert "$3" -resize "$5%" "$work/sig.png"',
            '  convert "$work/page.png" "$work/sig.png" -geometry "+$4+$6" -composite "$work/step.png"',
            'else',
            '  cp "$work/page.png" "$work/step.png"',
            'fi',
            'if [ -n "$7" ]; then',
            '  convert "$work/step.png" -gravity NorthWest -pointsize "$10" -fill black -annotate "+$8+$9" "$7" "$work/composite.png"',
            'else',
            '  cp "$work/step.png" "$work/composite.png"',
            'fi',
            'if command -v img2pdf >/dev/null 2>&1; then',
            '  img2pdf "$work/composite.png" -o "$11"',
            'elif command -v gs >/dev/null 2>&1; then',
            '  gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$11" "$work/composite.png" 2>/dev/null || convert "$work/composite.png" "$11"',
            'else',
            '  convert "$work/composite.png" "$11"',
            'fi',
            'printf "%s\\n" "$11"'
        ].join("\n");
        saveProc.command = ["sh", "-c", script, "sh",
            file, String(page), signature || "", String(x), String(pct), String(y),
            fillText || "", String(textX), String(textY), String(textSize), out];
        saveProc.out = out;
        saveProc.running = true;
    }
    function saveSignedCopy() { save(); }

    Process {
        id: saveProc
        property string out: ""
        stdout: SplitParser { onRead: l => { if (l.trim()) root.signedFile = l.trim(); } }
        onExited: code => {
            root.saving = false;
            if (code === 0) {
                root.lastSaved = root.signedFile || root.out;
                root.status = Tr.t("Saved: ") + root.lastSaved;
                root.error = "";
                Quickshell.execDetached(["notify-send", "-a", "Signed", Tr.t("Signed copy saved"), root.lastSaved]);
            } else {
                root.error = Tr.t("Could not save the signed copy");
                root.status = "";
            }
        }
    }

    Component.onCompleted: { signature = defaultSignature(); }
}
