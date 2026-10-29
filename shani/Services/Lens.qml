pragma Singleton
// Lens: draw a box around anything on screen and get it back as something you
// can use — its text (Tesseract, local and offline), any QR code or barcode in
// it (zbar), and Chronoa to ask about it — Chronoa sees the pixels through its
// look_at_image skill (local vision model, behind the vision sense's consent).
// Selection is slurp, capture is grim over wlr-screencopy (niri offers both).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property string phase: "idle"       // idle | selecting | reading | ready | failed
    property string image: ""
    property string text: ""
    property string codes: ""           // decoded QR/barcodes, one per line
    property string error: ""
    property bool available: false      // slurp + grim + tesseract
    property bool hasZbar: false
    property string langs: "eng"

    // the region comes from slurp, or is given (`ipc call shani lensRegion "x,y wxh"`)
    function capture(geometry) {
        if (phase === "selecting" || phase === "reading")
            return;
        error = "";
        text = "";
        codes = "";
        image = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-lens-" + Date.now() + ".png";
        phase = geometry ? "reading" : "selecting";
        grab.command = ["sh", "-c", 'g="$2"; [ -n "$g" ] || g=$(slurp -d -b "#0b0d1288" -c "#7fd1c1ff" -w 2) || exit 3; grim -g "$g" "$1"',
                        "sh", image, geometry || ""];
        grab.running = true;
    }
    // a picture already on disk (a camera photo): read it like a selection
    function readFile(path) {
        if (phase === "selecting" || phase === "reading")
            return;
        error = "";
        text = "";
        codes = "";
        image = path;
        phase = "reading";
        ocr.running = true;
        if (hasZbar)
            zbar.running = true;
    }
    function close() {
        phase = "idle";
    }
    function copyText() {
        Quickshell.clipboardText = text;
    }
    function search() {
        Qt.openUrlExternally(Ui.webSearchUrl(text.trim().slice(0, 500)));
    }
    function translate() {
        Qt.openUrlExternally("https://translate.google.com/?sl=auto&tl=en&op=translate&text=" + encodeURIComponent(text.trim().slice(0, 2000)));
    }
    function openImage() {
        Qt.openUrlExternally("file://" + image);
    }
    function save() {
        Quickshell.execDetached(["sh", "-c", 'd="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$d" && cp "$1" "$d/Lens-$(date +%F-%H%M%S).png"', "sh", image]);
    }
    function ask(question) {
        const q = (question || "").trim() || "What is this, and what can I do with it?";
        // look_at_image (Chronoa's skill) shows the model the pixels; the OCR
        // text rides along so a text-only model still has something to read
        Chronoa.ask("I selected part of my screen with Lens. Look at it with look_at_image: " + image
            + (text.trim() ? "\nThe text in it reads:\n\"\"\"\n" + text.trim() + "\n\"\"\"" : "\nIt has no readable text.")
            + (codes ? "\nIt contains a code that decodes to: " + codes : "")
            + "\n\n" + q);
        close();
    }

    Process {
        id: grab
        onExited: code => {
            if (code !== 0) {
                // 3: selection cancelled (Escape) — not an error worth showing
                root.phase = code === 3 ? "idle" : "failed";
                root.error = code === 3 ? "" : "Could not capture the screen";
                return;
            }
            root.phase = "reading";
            ocr.running = true;
            if (root.hasZbar)
                zbar.running = true;
        }
    }
    Process {
        id: ocr
        command: ["tesseract", root.image, "-", "-l", root.langs]
        stdout: StdioCollector {
            onStreamFinished: {
                root.text = text.replace(/\f/g, "").replace(/\n{3,}/g, "\n\n").trim();
                root.phase = "ready";
            }
        }
        onExited: code => {
            if (code !== 0 && root.phase === "reading") {
                root.phase = "ready";
                root.error = "Text recognition failed";
            }
        }
    }
    Process {
        id: zbar
        command: ["zbarimg", "-q", "--raw", root.image]
        stdout: StdioCollector { onStreamFinished: root.codes = text.trim() }
    }

    // which tools are here, and which OCR languages (eng first, up to three)
    Process {
        running: true
        command: ["sh", "-c", "command -v slurp >/dev/null && command -v grim >/dev/null && command -v tesseract >/dev/null && echo ok; command -v zbarimg >/dev/null && echo zbar; tesseract --list-langs 2>/dev/null | tail -n +2"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.available = lines.indexOf("ok") >= 0;
                root.hasZbar = lines.indexOf("zbar") >= 0;
                const l = lines.filter(x => /^[a-z_]{3,}$/.test(x) && x !== "osd" && x !== "ok" && x !== "zbar");
                const ordered = (l.indexOf("eng") >= 0 ? ["eng"] : []).concat(l.filter(x => x !== "eng"));
                root.langs = ordered.slice(0, 3).join("+") || "eng";
            }
        }
    }
}
