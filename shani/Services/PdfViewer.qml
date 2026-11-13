pragma Singleton
// PDFs, as pictures (PdfViewer): poppler renders a document's pages to PNGs
// in ~/.cache/shani-pdf (pdftoppm -png -r 100) and the reader walks them —
// one cached page at a time, no PDF library in the shell. Papers/Evince
// parity on top: page thumbnails sidebar, text search (pdftotext -bbox word
// boxes highlighted over the page), outline/bookmarks (PyMuPDF), DjVu by
// ddjvu, everything else not PDF made a PDF by PyMuPDF; fit-width / fit-page, continuous scroll option,
// rotation, and print via `lp` (Printing.printFile backend). Shown by
// Modules/PdfReader/PdfReader.qml until closed.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string file: ""               // the document open, while shown
    // the PDF actually read: the file itself, or - for an e-book, a comic or a
    // DjVu - its PDF copy, made once and kept in the cache (convertProc), so
    // search, text, the outline and printing work the same for all of them
    property string pdf: ""
    // ---- a PDF's form (bridge/pdfform.py, PyMuPDF): its fields, what is typed in
    // them, and a filled copy saved beside the original ----
    readonly property string formTool: Quickshell.env("SHANI_PDFFORM_TOOL") || "/usr/lib/shani-shell/pdfform.py"
    property var formFields: []             // [{ name, label, type, value, options, page }]
    property var formValues: ({})           // name -> value, as filled in here
    property bool formShown: false
    property string formSaved: ""
    property string formError: ""
    function setField(name, value) { const v = Object.assign({}, formValues); v[name] = value; formValues = v; }
    function fieldValue(f) { return formValues[f.name] !== undefined ? formValues[f.name] : f.value; }
    function saveForm() {
        formSaved = "";
        formError = "";
        formFill.command = ["sh", "-c", 'printf "%s" "$3" | python3 "$1" fill "$2"', "sh", formTool, file, JSON.stringify(formValues)];
        formFill.running = true;
    }
    Process {
        id: formRead
        stdout: StdioCollector { onStreamFinished: { try { const f = JSON.parse(text); root.formFields = Array.isArray(f) ? f : []; } catch (e) { root.formFields = []; } } }
    }
    Process {
        id: formFill
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (r.saved) root.formSaved = r.saved; else root.formError = r.error || Tr.t("The copy could not be saved");
                } catch (e) { root.formError = Tr.t("The copy could not be saved"); }
            }
        }
    }
    readonly property var otherTypes: ["epub", "cbz", "cbr", "cb7", "cbt", "djvu", "djv", "xps", "oxps", "fb2", "mobi"]
    property var pages: []                  // rendered page PNGs, in order
    property int page: 0                    // which page is on screen (0-based)
    property bool loading: false            // pdftoppm is running
    property string error: ""               // last render failure, for the card
    property int rotation: 0                // 0 | 90 | 180 | 270, per document
    property string fitMode: "page"         // fit-page | fit-width | actual (fit-width/fit-page)
    property bool continuous: false          // continuous scroll option (all pages at once)
    property bool showSidebar: true          // page thumbnails sidebar
    property string searchText: ""          // last query
    property var searchMatches: []           // [{ page, x0, y0, x1, y1, pageW, pageH, word }]
    property int searchIndex: -1            // which match the highlight sits on
    property var searchWords: []            // every word from pdftotext -bbox, for search
    property var highlight: null            // current match's rect, overlaid on the page
    property var outline: []                // [{ level, page (0-based), title }] bookmarks
    property var pageTexts: []              // per-page plain text (pdftotext -layout), for the fallback
    property string printState: ""          // last print result (via lp)
    property string searchState: ""         // last search status, for the tests

    readonly property bool shown: file !== ""
    readonly property string name: file === "" ? "" : file.split("/").pop()
    readonly property int pageCount: pages.length
    readonly property string current: page >= 0 && page < pages.length ? pages[page] : ""
    readonly property string label: pages.length > 0 ? (page + 1) + " / " + pages.length : ""
    readonly property string searchLabel: searchMatches.length
        ? (searchIndex + 1) + " / " + searchMatches.length
        : (searchText !== "" && searchState !== "" ? searchState : "")

    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") || "/tmp") + "/.cache") + "/shani-pdf"

    function open(pdf) {
        if (!pdf)
            return;
        file = pdf;
        page = 0;
        pages = [];
        error = "";
        rotation = 0;
        fitMode = "page";
        continuous = false;
        showSidebar = true;
        searchText = "";
        searchMatches = [];
        searchIndex = -1;
        searchWords = [];
        highlight = null;
        outline = [];
        pageTexts = [];
        printState = "";
        searchState = "";
        formFields = [];
        formValues = {};
        formShown = false;
        formSaved = "";
        formError = "";
        loading = true;
        Ui.pdfReader = true;
        const ext = (pdf.split(".").pop() || "").toLowerCase();
        if (otherTypes.indexOf(ext) < 0) {
            root.pdf = pdf;
            renderPdf();
            return;
        }
        // an e-book (EPUB, FB2, MOBI), a comic (CBZ; CBR/CB7/CBT unpacked first), XPS or DjVu: a PDF copy
        root.pdf = "";
        convertProc.command = ["sh", "-c", 'in=$1; ext=$2; tool=$4; d="$3/converted"; mkdir -p "$d"; out="$d/$(printf %s "$in" | md5sum | cut -c1-16).pdf"
            [ -s "$out" ] && [ "$out" -nt "$in" ] && { printf %s "$out"; exit 0; }
            case "$ext" in
            djvu|djv) command -v ddjvu >/dev/null || { echo "needs ddjvu (djvulibre)" >&2; exit 3; }; ddjvu -format=pdf "$in" "$out.part" ;;
            cbr|cb7|cbt) t=$(mktemp -d); bsdtar -xf "$in" -C "$t" 2>/dev/null
                find "$t" -type f | grep -iE "[.](jpe?g|png|webp|gif)$" | sort -V > "$t.list"
                set --; while IFS= read -r f; do set -- "$@" "$f"; done < "$t.list"
                [ $# -gt 0 ] && python3 "$tool" topdf "$out.part" "$@" >/dev/null; rm -rf "$t" "$t.list" ;;
            *) python3 "$tool" topdf "$out.part" "$in" >/dev/null ;;
            esac
            [ -s "$out.part" ] && mv "$out.part" "$out" && printf %s "$out"', "sh", pdf, ext, root.cacheDir, root.formTool];
        convertProc.running = true;
    }
    function renderPdf() {
        render.command = ["sh", "-c", 'mkdir -p "$1" && rm -f "$1"/*.png && pdftoppm -png -r 100 "$2" "$3"; ls -1 "$1"/*.png 2>/dev/null | sort', "sh", root.cacheDir, root.pdf, root.cacheDir + "/page"];
        render.running = true;
    }
    Process {
        id: convertProc
        stdout: StdioCollector { id: convertOut }
        stderr: StdioCollector { id: convertErr }
        onExited: code => {
            const out = convertOut.text.trim();
            if (code === 0 && out) {
                root.pdf = out;
                root.renderPdf();
            } else {
                root.loading = false;
                root.error = convertErr.text.trim().split("\n").pop() || Tr.t("This document could not be read");
            }
        }
    }
    function close() {
        file = "";
        pages = [];
        page = 0;
        error = "";
        loading = false;
        rotation = 0;
        searchMatches = [];
        searchWords = [];
        highlight = null;
        outline = [];
        pageTexts = [];
        searchText = "";
        searchIndex = -1;
        Ui.pdfReader = false;
    }
    function goTo(i) {
        if (!pages.length)
            return;
        page = Math.max(0, Math.min(pages.length - 1, i));
    }
    function nextPage() { goTo(page + 1); }
    function prevPage() { goTo(page - 1); }
    // jump-to-page box (1-based, as printed on the page)
    function jumpTo(n) { goTo((parseInt(n) || 1) - 1); }
    function goToPage(n) { jumpTo(n); }

    // ---- rotation / fit / continuous / sidebar -------------------------------
    function rotate() { rotation = (rotation + 90) % 360; }
    function rotateCCW() { rotation = (rotation - 90 + 360) % 360; }
    function setFit(mode) {
        if (mode === "page" || mode === "fit-page" || mode === "fit") fitMode = "page";
        else if (mode === "width" || mode === "fit-width") fitMode = "width";
        else if (mode === "actual" || mode === "100") fitMode = "actual";
        else fitMode = mode;
    }
    function toggleContinuous() { continuous = !continuous; }
    function toggleSidebar() { showSidebar = !showSidebar; }
    function goToOutline(i) {
        const o = outline[i];
        if (o) goTo(o.page);
    }

    // ---- text search (pdftotext) ---------------------------------------------
    // Primary: `pdftotext -bbox` word boxes, so the current match can be drawn
    // over the page image. Fallback: `pdftotext -layout` page texts, which
    // gives the pages holding the term (page-level jump, no box) when -bbox
    // finds nothing.
    function search(q) {
        const query = String(q || "").trim();
        searchText = query;
        if (query === "") {
            clearSearch();
            return;
        }
        const needle = query.toLowerCase();
        const hits = [];
        for (const w of searchWords) {
            if (String(w.text || w.word || "").toLowerCase().indexOf(needle) >= 0)
                hits.push(w);
        }
        searchMatches = hits;
        if (hits.length > 0) {
            searchIndex = 0;
            highlight = hits[0];
            page = hits[0].page;
            searchState = hits.length + " found";
        } else if (pageTexts.length > 0) {
            // fallback: jump through the pages whose -layout text holds the term
            const pagesWith = [];
            for (let p = 0; p < pageTexts.length; p++)
                if (String(pageTexts[p] || "").toLowerCase().indexOf(needle) >= 0)
                    pagesWith.push(p);
            searchMatches = pagesWith.map(p => ({ page: p, x0: 0, y0: 0, x1: 0, y1: 0, pageW: 100, pageH: 100, word: query }));
            searchIndex = 0;
            if (pagesWith.length > 0) {
                highlight = searchMatches[0];
                page = pagesWith[0];
                searchState = pagesWith.length + " pages";
            } else {
                searchState = Tr.t("Not found");
                highlight = null;
            }
        } else {
            searchIndex = -1;
            highlight = null;
            searchState = Tr.t("Not found");
        }
    }
    function findNext() {
        if (!searchMatches.length)
            return;
        searchIndex = (searchIndex + 1) % searchMatches.length;
        highlight = searchMatches[searchIndex];
        page = highlight.page;
    }
    function findPrev() {
        if (!searchMatches.length)
            return;
        searchIndex = (searchIndex - 1 + searchMatches.length) % searchMatches.length;
        highlight = searchMatches[searchIndex];
        page = highlight.page;
    }
    function clearSearch() {
        searchText = "";
        searchMatches = [];
        searchIndex = -1;
        highlight = null;
        searchState = "";
    }

    // ---- print (CUPS `lp`, via the Printing.printFile backend) ---------------
    function printFile() {
        if (!file)
            return;
        Printing.printFile(root.pdf || file);       // an e-book prints from its PDF copy
        printState = "printing " + name;
        printProc.command = ["sh", "-c", "lpstat -o 2>/dev/null | grep -c . || true"];
        printProc.running = true;
    }
    Process { id: printProc; onExited: code => root.printState = code === 0 ? "printed " + root.name : "print failed"; }
    // print_file: the shell has no print dialog — `lp` is enough (CUPS).

    Process {
        id: render
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                const items = text.trim().split("\n").filter(s => s);
                root.pages = items;
                root.page = 0;
                root.error = items.length === 0 ? Tr.t("This document could not be read") : "";
                if (items.length > 0 && root.file !== "") {
                    root._fetchTexts();
                    root._fetchOutline();
                    // a real PDF may have a form (a copy made from an e-book has none)
                    if (root.pdf === root.file) {
                        formRead.command = ["python3", root.formTool, "fields", root.file];
                        formRead.running = true;
                    }
                }
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

    // pdftotext -layout: per-page text (the search fallback, and reading the
    // document without rendering a page at all)
    function _fetchTexts() {
        if (!file) return;
        textsProc.command = ["sh", "-c", 'pdftotext -layout "$1" - 2>/dev/null || echo', "sh", root.pdf];
        textsProc.running = true;
    }
    Process {
        id: textsProc
        stdout: StdioCollector {
            onStreamFinished: {
                // \f separates the pages; empty chunks between them are skipped
                const chunks = String(text || "").split("\f");
                const out = [];
                for (const c of chunks)
                    if (c.trim() !== "") out.push(c);
                if (out.length) root.pageTexts = out;
                // box search needs the bbox pass too
                if (root.file !== "") {
                    bboxProc.command = ["sh", "-c", 'pdftotext -bbox "$1" - 2>/dev/null || echo', "sh", root.pdf];
                    bboxProc.running = true;
                }
            }
        }
    }

    // pdftotext -bbox: <page width height><word xMin yMin xMax yMax>text</word>
    // The overlay box is the word's rect over its page size (points, 72 dpi);
    // the reader maps it onto the rendered PNG (100 dpi, letterboxed).
    Process {
        id: bboxProc
        stdout: StdioCollector {
            onStreamFinished: {
                const xml = String(text || "");
                if (xml.indexOf("<page") < 0 || xml.indexOf("<word") < 0)
                    return;
                const words = [];
                // split into pages first, so each word knows its page size
                const pageRe = /<page width="([\d.]+)" height="([\d.]+)">([\s\S]*?)<\/page>/g;
                let pm;
                let p = 0;
                while ((pm = pageRe.exec(xml)) !== null) {
                    const pw = parseFloat(pm[1]) || 100;
                    const ph = parseFloat(pm[2]) || 100;
                    const body = pm[3] || "";
                    const wordRe = /<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]+)<\/word>/g;
                    let wm;
                    while ((wm = wordRe.exec(body)) !== null) {
                        words.push({ page: p, x0: parseFloat(wm[1]), y0: parseFloat(wm[2]), x1: parseFloat(wm[3]), y1: parseFloat(wm[4]),
                                     pageW: pw, pageH: ph, text: wm[5], word: wm[5] });
                    }
                    p++;
                }
                root.searchWords = words;
                if (root.searchText !== "") root.search(root.searchText);
            }
        }
    }

    // outline / bookmarks: pdftoppm alone gives no outline, so ask PyMuPDF
    // for its toc. No
    // tool, no outline; the reader then simply shows the thumbnails.
    function _fetchOutline() {
        if (!file) return;
        outlineProc.command = ["sh", "-c",
            'python3 -c \'import pymupdf, sys; d=pymupdf.open(sys.argv[1]); [print(f"{lvl}\\t{pg-1}\\t{title}") for lvl, title, pg in d.get_toc()]\' "$1" 2>/dev/null '
            + '|| true',
            "sh", root.pdf];
        outlineProc.running = true;
    }
    Process {
        id: outlineProc
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = [];
                for (const line of String(text || "").split("\n")) {
                    const parts = line.split("\t");
                    if (parts.length < 3)
                        continue;
                    const lvl = parseInt(parts[0]);
                    const pg = parseInt(parts[1]);
                    const title = parts.slice(2).join("\t").trim();
                    if (!title || isNaN(pg))
                        continue;
                    rows.push({ level: Math.max(0, Math.min(8, lvl)), page: Math.max(0, pg), title: title });
                }
                if (rows.length) root.outline = rows;
            }
        }
    }
}
