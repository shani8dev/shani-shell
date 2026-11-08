pragma Singleton
// PDFs, as pictures (PdfViewer): poppler renders a document's pages to PNGs
// in ~/.cache/shani-pdf (pdftoppm -png -r 100) and the reader walks them —
// one cached page at a time, no PDF library in the shell. Shown by
// Modules/PdfReader/PdfReader.qml until closed.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string file: ""               // the PDF open, while shown
    property var pages: []                  // rendered page PNGs, in order
    property int page: 0                    // which page is on screen (0-based)
    property bool loading: false            // pdftoppm is running
    property string error: ""               // last render failure, for the card

    readonly property bool shown: file !== ""
    readonly property string name: file === "" ? "" : file.split("/").pop()
    readonly property int pageCount: pages.length
    readonly property string current: page >= 0 && page < pages.length ? pages[page] : ""
    readonly property string label: pages.length > 0 ? (page + 1) + " / " + pages.length : ""

    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") || "/tmp") + "/.cache") + "/shani-pdf"

    function open(pdf) {
        if (!pdf)
            return;
        file = pdf;
        page = 0;
        pages = [];
        error = "";
        loading = true;
        render.command = ["sh", "-c", 'mkdir -p "$1" && rm -f "$1"/*.png && pdftoppm -png -r 100 "$2" "$3"; ls -1 "$1"/*.png 2>/dev/null | sort', "sh", root.cacheDir, pdf, root.cacheDir + "/page"];
        render.running = true;
    }
    function close() {
        file = "";
        pages = [];
        page = 0;
        error = "";
        loading = false;
    }
    function goTo(i) {
        if (!pages.length)
            return;
        page = Math.max(0, Math.min(pages.length - 1, i));
    }
    function nextPage() { goTo(page + 1); }
    function prevPage() { goTo(page - 1); }

    Process {
        id: render
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                const items = text.trim().split("\n").filter(s => s);
                root.pages = items;
                root.page = 0;
                root.error = items.length === 0 ? Tr.t("This PDF could not be read") : "";
            }
        }
        onExited: code => {
            // pdftoppm failed and left nothing: say so instead of a blank page
            if (code !== 0 && root.pages.length === 0) {
                root.loading = false;
                root.error = Tr.t("This PDF could not be read");
            }
        }
    }
}
