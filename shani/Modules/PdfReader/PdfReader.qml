// A PDF, page by page (PdfReader) — Papers/Evince parity: page thumbnails
// sidebar, text search (pdftotext -bbox, word highlighted over the page,
// with a jump-to-page box as well), outline/bookmarks, fit-width/fit-page,
// continuous scroll option, rotation, print button (lp via Printing).
// poppler's PNGs in ~/.cache/shani-pdf, ← → or wheel to turn, Esc closes,
// Ctrl+O opens a file (also offered in the empty/error state).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Document Viewer"
    property string note: ""
    // one extras panel at a time: bookmarks, links, attachments, annotations
    property string extraPanel: ""
    property bool mergeSplitShown: false
    property bool printShown: false
    function toggleExtra(name) { extraPanel = extraPanel === name ? "" : name; }
    // jump from the document to its folder in Files, with the file chosen
    function reveal(path) {
        const p = String(path || ""); if (!p.startsWith("/")) return;
        const at = p.lastIndexOf("/"); Files.show(at === 0 ? "/" : p.substring(0, at)); Files.select(p, "single");
    }
    function pick() {
        FilePicker.open({ mode: "open", filters: ["pdf"], title: "Open a PDF",
                          onPicked: paths => { if (paths && paths.length) PdfViewer.open(paths[0]); } });
    }
    function saveAttachment(index, name) {
        FilePicker.open({
            mode: "save",
            title: Tr.t("Save embedded file"),
            defaultName: name || "attachment",
            onPicked: paths => { if (paths && paths.length) PdfViewer.saveAttachment(index, paths[0]); }
        });
    }
    // the page is already rendered to a PNG; save that, without a second render
    function savePageImage() {
        if (!PdfViewer.current) { win.note = Tr.t("There is no page to save"); return; }
        const base = (PdfViewer.name || "page").replace(/\.[^.]+$/, "");
        FilePicker.open({
            mode: "save",
            title: Tr.t("Save this page as an image"),
            defaultName: base + "-page-" + (PdfViewer.page + 1) + ".png",
            startPath: (Quickshell.env("HOME") || "") + "/Pictures",
            filters: ["png"],
            onPicked: paths => { if (paths && paths.length) PdfViewer.savePageImage(paths[0]); }
        });
    }
    // merge / split: the service already has merge() and split(); this is the
    // UI that fills their arguments. Paths arrive from FilePicker, never from
    // a string typed into a command line.
    property var mergePaths: []
    property string mergeOut: ""
    property string splitPrefix: (Quickshell.env("HOME") || "") + "/Pages/page"
    property string splitRange: ""
    function doMerge() {
        PdfViewer.mergeFiles = win.mergePaths.slice();
        PdfViewer.mergeOutput = win.mergeOut;
        PdfViewer.merge();
        win.mergeSplitShown = false;
        win.note = Tr.t("Merging %1 PDFs…", win.mergePaths.length);
    }
    function doSplit() {
        PdfViewer.split(PdfViewer.file, win.splitPrefix, win.splitRange);
        win.mergeSplitShown = false;
        win.note = Tr.t("Splitting…");
    }
    // status line for annotation saves and errors
    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: Theme.px(12) }
        z: 20
        visible: win.note !== ""
        implicitWidth: noteText.implicitWidth + 20
        implicitHeight: Theme.px(30)
        radius: Theme.px(8)
        color: Theme.alpha(Theme.surface1, 0.96)
        border.width: 1
        border.color: Theme.border
        Text { id: noteText; anchors.centerIn: parent; text: win.note; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        Timer { interval: 4000; onTriggered: win.note = ""; running: parent.visible }
    }
    visible: PdfViewer.shown
    onGone: PdfViewer.close()
    margins: 0
    implicitWidth: Theme.px(960)
    implicitHeight: Theme.px(760)
    property bool pdfAnnoMode: false
    // ---- markup strokes, the same model as the image Viewer --------------------
    property var strokes: []
    property string tool: "pen"         // pen | highlight | line | arrow | box | text | blur
    property string penColor: "#e5484d"
    property real penSize: 0.008
    property string textInput: ""
    readonly property bool twoPoint: tool === "line" || tool === "arrow" || tool === "box" || tool === "blur"
    function addStroke(pts) {
        if (!pts || !pts.length) return;
        const p = twoPoint && pts.length > 1 ? [pts[0], pts[pts.length - 1]] : pts;
        strokes = strokes.concat([{ kind: tool, color: penColor, size: penSize, points: p,
                                    text: tool === "text" ? textInput : "" }]);
        textInput = "";
    }
    function undoStroke() { if (strokes.length) strokes = strokes.slice(0, -1); }
    function clearMarks() { strokes = []; }
    readonly property string annTool: Quickshell.env("SHANI_PDFANNOTATE_TOOL") || "/usr/lib/shani-shell/pdf-annotate.py"
    function markPage() {
        if (!PdfViewer.file || strokes.length === 0) return;
        const out = PdfViewer.file.replace(/\.pdf$/i, "") + " (annotated).pdf";
        annoProc.command = ["python3", annTool, "annotate", PdfViewer.file, String(PdfViewer.page + 1), out];
        annoProc.payload = JSON.stringify({ strokes: strokes });
        annoProc.running = true;
    }
    Process {
        id: annoProc
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload); payload = ""; stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {}; try { r = JSON.parse(text); } catch (e) { r = { error: text.trim() }; }
                if (r.saved) { win.pdfAnnoMode = false; PdfViewer.close(); PdfViewer.open(r.saved); win.note = Tr.t("Saved %1", r.saved); }
                else win.note = r.error || Tr.t("Could not save the annotation");
            }
        }
    }
    // Export the current page to a PNG for annotation in the image Viewer
    function pdfExportPage(path) {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && pdftoppm -f $((PdfViewer.page+1)) -l $((PdfViewer.page+1)) -png "$PdfViewer.file" "${1%.png}" 2>/dev/null', "sh", path]);
        pdfAnnoMode = false;
        // Open the exported page in the image Viewer
        const base = path.replace(/\.png$/, "");
        Ui.closeAll();
        Viewer.open(base + "-" + String(PdfViewer.page + 1).padStart(4, "0") + ".png");
    }
    // blur behind the card, as on every shell surface (ext-background-effect)

    // ---- merge / split ---------------------------------------------------------
    Glass {
        id: mergeBox
        parent: win.contentItem
        visible: win.mergeSplitShown
        z: 41
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(460))
        height: mergeCol.implicitHeight + 28
        anchors.centerIn: parent
        ColumnLayout {
            id: mergeCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: Tr.t("Merge / Split PDFs"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
                IconButton { icon: "window-close"; size: Theme.px(24); tip: Tr.t("Close"); onClicked: win.mergeSplitShown = false }
            }
            SectionTitle { Layout.fillWidth: true; text: Tr.t("Merge") }
            Text {
                Layout.fillWidth: true
                text: win.mergePaths.length ? Tr.t("%1 PDFs chosen", win.mergePaths.length) : Tr.t("Choose two or more PDFs")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: Tr.t("Choose PDFs…")
                    flat: true
                    onClicked: FilePicker.open({ mode: "open", multiple: true, filters: ["pdf"], title: Tr.t("PDFs to merge"),
                        onPicked: paths => { if (paths && paths.length) win.mergePaths = paths; } })
                }
                Button {
                    text: win.mergeOut ? Tr.t("Saving to %1", win.mergeOut.split("/").pop()) : Tr.t("Save as…")
                    flat: true
                    onClicked: FilePicker.open({ mode: "save", title: Tr.t("Merged PDF"), defaultName: "merged.pdf",
                        onPicked: paths => { if (paths && paths.length) win.mergeOut = paths[0]; } })
                }
                Item { Layout.fillWidth: true }
                Button { kind: "primary"; text: Tr.t("Merge"); enabled: win.mergePaths.length >= 2 && win.mergeOut !== ""; onClicked: win.doMerge() }
            }
            SectionTitle { Layout.fillWidth: true; text: Tr.t("Split") }
            Text {
                Layout.fillWidth: true
                text: PdfViewer.name ? Tr.t("Split %1", PdfViewer.name) : Tr.t("Open a PDF to split it")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                elide: Text.ElideMiddle
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Output prefix (e.g. ~/Pages/page)")
                label: Tr.t("Output prefix")
                text: win.splitPrefix
                onTextChanged: win.splitPrefix = text
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Page range (e.g. 1-5), or all")
                label: Tr.t("Page range")
                text: win.splitRange
                onTextChanged: win.splitRange = text
            }
            Button { Layout.fillWidth: true; kind: "primary"; text: Tr.t("Split into pages"); enabled: PdfViewer.file !== ""; onClicked: win.doSplit() }
        }
    }

    // the document's properties (pdfinfo), over the page until closed
    Glass {
        id: infoBox
        parent: win.contentItem
        visible: PdfViewer.info !== null
        z: 40
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(440))
        height: infoCol.implicitHeight + 28
        anchors.centerIn: parent
        ColumnLayout {
            id: infoCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(4)
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: Tr.t("Document properties"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
                IconButton { icon: "window-close"; size: Theme.px(26); tip: Tr.t("Close"); onClicked: PdfViewer.info = null }
            }
            Repeater {
                model: PdfViewer.info || []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text { Layout.preferredWidth: Theme.px(120); text: Tr.t(modelData[0]); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                    Text { Layout.fillWidth: true; text: modelData[1]; wrapMode: Text.WrapAnywhere; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                }
            }
        }
    }

    // print options: CUPS accepts a page range; validate it in the service
    // before it becomes an `lp -o page-ranges=…` argument
    Glass {
        id: printBox
        parent: win.contentItem
        visible: win.printShown
        z: 41
        strong: true
        solid: true
        radius: Theme.px(12)
        width: Math.min(parent.width - 40, Theme.px(400))
        height: printCol.implicitHeight + 28
        anchors.centerIn: parent
        ColumnLayout {
            id: printCol
            anchors.fill: parent
            anchors.margins: Theme.px(14)
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Print") + (PdfViewer.name !== "" ? "  ·  " + PdfViewer.name : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                }
                IconButton { icon: "window-close"; size: Theme.px(24); tip: Tr.t("Close"); onClicked: win.printShown = false }
            }
            TextField {
                id: printRangeField
                Layout.fillWidth: true
                placeholder: Tr.t("Page range (e.g. 1-5), or all")
                label: Tr.t("Page range")
            }
            Button {
                Layout.fillWidth: true
                kind: "primary"
                text: Tr.t("Print")
                enabled: PdfViewer.validPageRange(printRangeField.text, PdfViewer.pageCount)
                onClicked: { PdfViewer.printFile(printRangeField.text); win.printShown = false; }
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: printShown ? printShown = false : (PdfViewer.info !== null ? PdfViewer.info = null : PdfViewer.close())
        Keys.onRightPressed: PdfViewer.nextSpread()
        Keys.onLeftPressed: PdfViewer.prevSpread()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_O && (e.modifiers & Qt.ControlModifier)) win.pick();
            else if (e.key === Qt.Key_L && (e.modifiers & Qt.ControlModifier)) win.reveal(PdfViewer.file);
            else if (e.key === Qt.Key_PageDown) PdfViewer.nextSpread();
            else if (e.key === Qt.Key_PageUp) PdfViewer.prevSpread();
            else if (e.key === Qt.Key_R && (e.modifiers & Qt.ShiftModifier)) PdfViewer.rotateCCW();
            else if (e.key === Qt.Key_R) PdfViewer.rotate();
            else if (e.key === Qt.Key_F) PdfViewer.setFit("page");
            else if (e.key === Qt.Key_W) PdfViewer.setFit("width");
            else if (e.key === Qt.Key_P) PdfViewer.printFile();
            else if (e.key === Qt.Key_BracketLeft) PdfViewer.navBack();
            else if (e.key === Qt.Key_BracketRight) PdfViewer.navForward();
            else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) PdfViewer.setZoom(PdfViewer.zoom * 1.25);
            else if (e.key === Qt.Key_Minus) PdfViewer.setZoom(PdfViewer.zoom / 1.25);
            else if (e.key === Qt.Key_0) PdfViewer.setZoom(1);
        }
    }
    // properties and panels belong to one document, strokes to one page:
    // neither may survive opening another file or turning a page
    Connections {
        target: PdfViewer
        function onPageSaveStateChanged() {
            if (PdfViewer.pageSaveState === "ok")
                win.note = Tr.t("Saved %1", PdfViewer.pageSavePath.split("/").pop());
            else if (PdfViewer.pageSaveState === "error")
                win.note = PdfViewer.pageSaveError || Tr.t("Could not save this page");
        }
        function onFileChanged() {
            // the service drops its query on open(); the fields must not keep
            // showing the previous document's search and page number
            if (searchField) searchField.text = "";
            if (jumpField) jumpField.text = "";
            PdfViewer.info = null;
            win.extraPanel = "";
            win.mergeSplitShown = false;
            win.printShown = false;
            win.pdfAnnoMode = false;
            win.clearMarks();
            win.note = "";
        }
        function onPageChanged() { if (win.strokes.length) win.clearMarks(); }
    }
    Item {
        id: blurCard
        anchors.fill: parent
        MouseArea { anchors.fill: parent }       // clicks inside do not close it
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(8)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                IconButton { icon: "go-first"; size: Theme.px(28); tip: Tr.t("First page"); onClicked: PdfViewer.firstPage() }
                IconButton { icon: "go-previous"; size: Theme.px(28); tip: Tr.t("Previous page"); onClicked: PdfViewer.prevSpread() }
                IconButton { icon: "edit-undo"; size: Theme.px(28); tip: Tr.t("Back"); keys: "["; enabled: PdfViewer.canNavBack; onClicked: PdfViewer.navBack() }
                IconButton { icon: "edit-redo"; size: Theme.px(28); tip: Tr.t("Forward"); keys: "]"; enabled: PdfViewer.canNavForward; onClicked: PdfViewer.navForward() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: PdfViewer.name + (PdfViewer.label !== "" ? "  ·  " + PdfViewer.label : "")
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-next"; size: Theme.px(28); tip: Tr.t("Next page"); onClicked: PdfViewer.nextSpread() }
                IconButton { icon: "go-last"; size: Theme.px(28); tip: Tr.t("Last page"); onClicked: PdfViewer.lastPage() }
                IconButton { icon: "document-open"; size: Theme.px(28); tip: Tr.t("Toggle thumbnails"); on: PdfViewer.showSidebar; onClicked: PdfViewer.toggleSidebar() }
                IconButton { icon: "printer"; size: Theme.px(28); tip: Tr.t("Print (P)"); on: win.printShown; onClicked: win.printShown = !win.printShown }
                IconButton { icon: "draw-freehand"; size: Theme.px(28); tip: Tr.t("Mark up this page"); on: win.pdfAnnoMode; onClicked: { win.pdfAnnoMode = !win.pdfAnnoMode; } }
                IconButton { icon: "weather-clear-night"; size: Theme.px(28); tip: Tr.t("Night mode"); on: PdfViewer.night; onClicked: PdfViewer.setNight(!PdfViewer.night) }
                IconButton { icon: "format-text-direction-ltr"; size: Theme.px(28); tip: Tr.t("Read as text (select and copy)"); on: PdfViewer.textMode; onClicked: PdfViewer.textMode = !PdfViewer.textMode }
                IconButton { icon: "edit-copy"; size: Theme.px(28); tip: Tr.t("Copy this page's text"); onClicked: win.note = PdfViewer.copyPageText() ? Tr.t("Copied this page's text") : Tr.t("This page has no text to copy") }
                IconButton { icon: "document-save-as"; size: Theme.px(28); tip: Tr.t("Save this page as image…"); enabled: PdfViewer.current !== ""; onClicked: win.savePageImage() }
                IconButton { icon: "document-properties"; size: Theme.px(28); tip: Tr.t("Document properties"); onClicked: PdfViewer.showInfo() }
                IconButton { icon: "folder-open"; size: Theme.px(28); tip: Tr.t("Show in Files"); enabled: PdfViewer.file !== ""; onClicked: win.reveal(PdfViewer.file) }
                // a form: fill it in, save a filled copy
                Button {
                    visible: PdfViewer.formFields.length > 0
                    text: Tr.t("Fill in (%1)", PdfViewer.formFields.length)
                    kind: PdfViewer.formShown ? "primary" : ""
                    onClicked: PdfViewer.formShown = !PdfViewer.formShown
                }
                IconButton { icon: "user-bookmarks"; size: Theme.px(28); tip: Tr.t("Your bookmarks"); on: win.extraPanel === "bookmarks"; onClicked: win.toggleExtra("bookmarks") }
                IconButton { icon: "insert-link"; size: Theme.px(28); tip: Tr.t("Links in this PDF"); on: win.extraPanel === "links"; onClicked: win.toggleExtra("links") }
                IconButton { icon: "mail-attachment"; size: Theme.px(28); tip: Tr.t("Embedded attachments"); on: win.extraPanel === "attachments"; onClicked: win.toggleExtra("attachments") }
                IconButton { icon: "view-list"; size: Theme.px(28); tip: Tr.t("Annotations"); on: win.extraPanel === "annotations"; onClicked: win.toggleExtra("annotations") }
                Button { text: Tr.t("Merge / Split…"); flat: true; onClicked: win.mergeSplitShown = true }
            }

            // search bar: find text (pdftotext -bbox) + jump-to-page box
            RowLayout {
                visible: PdfViewer.shown
                Layout.fillWidth: true
                spacing: Theme.px(6)
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Find in document…")
                    label: Tr.t("Find in document")
                    onAccepted: PdfViewer.search(searchField.text)
                }
                IconButton { icon: "go-up"; size: Theme.px(28); tip: Tr.t("Find previous"); onClicked: PdfViewer.findPrev() }
                IconButton { icon: "go-down"; size: Theme.px(28); tip: Tr.t("Find next"); onClicked: PdfViewer.findNext() }
                Choice {
                    text: Tr.t("Case")
                    selected: PdfViewer.caseSensitive
                    onClicked: { PdfViewer.caseSensitive = !PdfViewer.caseSensitive; if (PdfViewer.searchText) PdfViewer.search(PdfViewer.searchText); }
                }
                Choice {
                    text: Tr.t("Word")
                    selected: PdfViewer.wholeWord
                    onClicked: { PdfViewer.wholeWord = !PdfViewer.wholeWord; if (PdfViewer.searchText) PdfViewer.search(PdfViewer.searchText); }
                }
                Choice {
                    text: Tr.t("Wrap")
                    selected: PdfViewer.wrapSearch
                    onClicked: PdfViewer.wrapSearch = !PdfViewer.wrapSearch
                }
                Text {
                    text: PdfViewer.searchLabel !== "" ? PdfViewer.searchLabel : (PdfViewer.searchState !== "" ? PdfViewer.searchState : PdfViewer.label)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                TextField {
                    id: jumpField
                    Layout.preferredWidth: Theme.px(80)
                    placeholder: Tr.t("Page…")
                    label: Tr.t("Go to page")
                    onAccepted: PdfViewer.jumpTo(jumpField.text)
                }
                IconButton { icon: "go-next"; size: Theme.px(28); tip: Tr.t("Go to page"); onClicked: PdfViewer.jumpTo(jumpField.text) }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(8)

                // page thumbnails sidebar (+ outline/bookmarks underneath)
                Rectangle {
                    visible: PdfViewer.showSidebar
                    Layout.preferredWidth: Theme.px(132)
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    clip: true
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(4)
                        spacing: Theme.px(4)
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            contentWidth: thumbCol.width
                            contentHeight: thumbCol.height
                            Column {
                                id: thumbCol
                                spacing: Theme.px(4)
                                Repeater {
                                    model: PdfViewer.pages
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        width: Theme.px(116)
                                        height: Theme.px(150)
                                        radius: Theme.radiusSmall
                                        color: index === PdfViewer.page ? Theme.alpha(Theme.accent, 0.22) : Theme.surface1
                                        border.width: index === PdfViewer.page ? 2 : 0
                                        border.color: Theme.accent
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: Theme.px(5)
                                            source: "file://" + modelData.split("/").map(encodeURIComponent).join("/")
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            cache: true
                                            asynchronous: true
                                            sourceSize: Qt.size(240, 300)
                                        }
                                        Text {
                                            anchors.bottom: parent.bottom
                                            anchors.right: parent.right
                                            anchors.margins: Theme.px(4)
                                            text: String(index + 1)
                                            color: Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(10) * Theme.fontScale
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: PdfViewer.goTo(index)
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: Tr.t("Page %1", index + 1)
                                        KeyFocus { onActivated: PdfViewer.goTo(index) }
                                    }
                                }
                            }
                        }
                        // outline / bookmarks (PyMuPDF)
                        Rectangle {
                            visible: PdfViewer.outline.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(140)
                            radius: Theme.radiusSmall
                            color: Theme.surface1
                            clip: true
                            Flickable {
                                anchors.fill: parent
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                contentWidth: outlineCol.width
                                contentHeight: outlineCol.height
                                Column {
                                    id: outlineCol
                                    spacing: 1
                                    Repeater {
                                        model: PdfViewer.outline
                                        Text {
                                            required property var modelData
                                            required property int index
                                            width: Theme.px(110)
                                            text: "  ".repeat(modelData.level) + modelData.title
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(10) * Theme.fontScale
                                            elide: Text.ElideRight
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: PdfViewer.goToOutline(index)
                                            }
                                            Accessible.role: Accessible.Button
                                            Accessible.name: modelData.title
                                            KeyFocus { onActivated: PdfViewer.goToOutline(index) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // main page: single page, or the continuous scroll column
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    clip: true

                    // single page (with the search highlight over it)
                    Rectangle {
                        visible: !PdfViewer.continuous
                        anchors.fill: parent
                        color: "transparent"
                        // zoomed: the page larger than the view, dragged around (a finger,
                        // the mouse); fitted, it is the view's size and nothing moves
                        Flickable {
                            id: pageFlick
                            anchors.fill: parent
                            clip: true
                            contentWidth: width * PdfViewer.zoom
                            contentHeight: height * PdfViewer.zoom
                            interactive: PdfViewer.zoom > 1.01
                            boundsBehavior: Flickable.StopAtBounds
                            // a new zoom keeps the middle of the page in the middle of the view
                            property real centreX: 0.5
                            property real centreY: 0.5
                            onContentXChanged: if (contentWidth > width) centreX = (contentX + width / 2) / contentWidth
                            onContentYChanged: if (contentHeight > height) centreY = (contentY + height / 2) / contentHeight
                            Connections {
                                target: PdfViewer
                                function onZoomChanged() {
                                    const cx = pageFlick.centreX, cy = pageFlick.centreY;
                                    Qt.callLater(() => {
                                        pageFlick.contentX = Math.max(0, Math.min(pageFlick.contentWidth - pageFlick.width, cx * pageFlick.contentWidth - pageFlick.width / 2));
                                        pageFlick.contentY = Math.max(0, Math.min(pageFlick.contentHeight - pageFlick.height, cy * pageFlick.contentHeight - pageFlick.height / 2));
                                    });
                                }
                            }
                            Item {
                                width: pageFlick.contentWidth
                                height: pageFlick.contentHeight
                        // read as text: the page's words, to select and copy
                        Flickable {
                            visible: PdfViewer.textMode && PdfViewer.current !== ""
                            anchors.fill: parent
                            anchors.margins: Theme.px(12)
                            z: 3
                            clip: true
                            contentWidth: width
                            contentHeight: pageTextEdit.implicitHeight
                            Rectangle { anchors.fill: parent; color: Theme.bg; z: -1 }
                            TextEdit {
                                id: pageTextEdit
                                width: parent.width
                                readOnly: true
                                selectByMouse: true
                                selectByKeyboard: true
                                wrapMode: TextEdit.Wrap
                                text: PdfViewer.pageTexts[PdfViewer.page] || Tr.t("This page has no text (a scan, perhaps).")
                                color: Theme.text
                                selectionColor: Theme.accent
                                font.family: Theme.mono
                                font.pixelSize: Theme.px(13) * Theme.fontScale
                                Accessible.role: Accessible.EditableText
                                Accessible.name: Tr.t("Page text")
                            }
                        }
                        // facing mode: the two adjacent PNGs the service already
                        // rendered. A missing second image leaves the first full
                        // width; a missing first leaves the second full width.
                        Image {
                            id: leftPageImage
                            visible: PdfViewer.facingActive && PdfViewer.spreadLeftPath !== ""
                            readonly property real m: PdfViewer.fitMode === "width" ? 2 : 10
                            x: m
                            y: m
                            width: (rightPageImage.visible ? parent.width / 2 : parent.width) - 2 * m
                            height: parent.height - 2 * m
                            source: PdfViewer.spreadLeftPath !== "" ? "file://" + PdfViewer.spreadLeftPath.split("/").map(encodeURIComponent).join("/") : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            cache: false
                            rotation: PdfViewer.rotation
                            transformOrigin: Item.Center
                            Accessible.role: Accessible.Graphic
                            Accessible.name: Tr.t("PDF page %1", PdfViewer.spreadLeft + 1)
                        }
                        Image {
                            id: rightPageImage
                            visible: PdfViewer.facingActive && PdfViewer.spreadRightPath !== ""
                            readonly property real m: PdfViewer.fitMode === "width" ? 2 : 10
                            x: (leftPageImage.visible ? parent.width / 2 : 0) + m
                            y: m
                            width: (leftPageImage.visible ? parent.width / 2 : parent.width) - 2 * m
                            height: parent.height - 2 * m
                            source: PdfViewer.spreadRightPath !== "" ? "file://" + PdfViewer.spreadRightPath.split("/").map(encodeURIComponent).join("/") : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            cache: false
                            rotation: PdfViewer.rotation
                            transformOrigin: Item.Center
                            Accessible.role: Accessible.Graphic
                            Accessible.name: Tr.t("PDF page %1", PdfViewer.spreadRight + 1)
                        }
                        Image {
                            id: pageImage
                            visible: !PdfViewer.facingActive && PdfViewer.current !== ""
                            anchors.fill: parent
                            anchors.margins: PdfViewer.fitMode === "width" ? 2 : 10
                            source: PdfViewer.current !== "" ? "file://" + PdfViewer.current.split("/").map(encodeURIComponent).join("/") : ""
                            fillMode: PdfViewer.fitMode === "actual" ? Image.PreserveAspectFit : Image.PreserveAspectFit
                            smooth: true
                            cache: false
                            rotation: PdfViewer.rotation
                            transformOrigin: Item.Center
                            Accessible.role: Accessible.Graphic
                            Accessible.name: "PDF page " + PdfViewer.label + ": " + PdfViewer.name
                        }
                        // the pdftotext -bbox word that find-next is sitting on
                        Rectangle {
                            visible: PdfViewer.highlight !== null && PdfViewer.highlight.x1 > PdfViewer.highlight.x0
                                && (!PdfViewer.facingActive || PdfViewer.highlight.page === PdfViewer.spreadLeft
                                    || PdfViewer.highlight.page === PdfViewer.spreadRight)
                            // in facing mode the box maps onto the half holding that page
                            readonly property bool inRight: PdfViewer.facingActive && PdfViewer.highlight
                                && PdfViewer.highlight.page === PdfViewer.spreadRight
                            readonly property real slotW: PdfViewer.facingActive && PdfViewer.highlight
                                && (PdfViewer.highlight.page === PdfViewer.spreadLeft || inRight) ? parent.width / 2 : parent.width
                            x: (inRight ? parent.width / 2 : 0)
                               + (PdfViewer.highlight ? (PdfViewer.highlight.x0 / PdfViewer.highlight.pageW) * slotW : 0)
                            y: PdfViewer.highlight ? (PdfViewer.highlight.y0 / PdfViewer.highlight.pageH) * parent.height : 0
                            width: PdfViewer.highlight ? ((PdfViewer.highlight.x1 - PdfViewer.highlight.x0) / PdfViewer.highlight.pageW) * slotW : 0
                            height: PdfViewer.highlight ? Math.max(4, ((PdfViewer.highlight.y1 - PdfViewer.highlight.y0) / PdfViewer.highlight.pageH) * parent.height) : 0
                            color: Theme.alpha(Theme.accent, 0.35)
                            border.width: 1
                            border.color: Theme.accent
                            radius: 2
                        }
                        MouseArea {
                            objectName: "nav:keys"          // the arrows and Page Up / Down turn pages (the window's Keys)
                            anchors.fill: parent
                            // Ctrl + wheel zooms; the wheel alone turns pages (scrolls, zoomed)
                            onWheel: w => {
                                if (w.modifiers & Qt.ControlModifier) PdfViewer.setZoom(PdfViewer.zoom * (w.angleDelta.y > 0 ? 1.25 : 0.8));
                                else if (PdfViewer.zoom > 1.01) w.accepted = false;
                                else if (w.angleDelta.y < 0) PdfViewer.nextSpread(); else PdfViewer.prevSpread();
                            }
                            onClicked: m => { if (PdfViewer.zoom > 1.01) return; if (m.x > width / 2) PdfViewer.nextSpread(); else PdfViewer.prevSpread(); }
                        }
                            }
                        }
                        // two fingers: zoom
                        PinchHandler {
                            target: null
                            property real from: 1
                            onActiveChanged: if (active) from = PdfViewer.zoom
                            onActiveScaleChanged: PdfViewer.setZoom(from * activeScale)
                        }
                        // ---- PDF annotation overlay: draw on the page image,
                        // then flatten into a new PDF with pdf-annotate.py ----
                        Canvas {
                            id: annoCanvas
                            anchors.fill: parent
                            z: 5
                            visible: win.pdfAnnoMode && !PdfViewer.textMode
                            property var live: []
                            function mark(ctx, kind, color, size, pts, words) {
                                if (!pts.length) return;
                                const m = Math.min(width, height), w = Math.max(1, size * m);
                                const P = pts.map(p => [p[0] * width, p[1] * height]);
                                const a = P[0], b = P[P.length - 1];
                                ctx.save();
                                ctx.strokeStyle = color; ctx.fillStyle = color;
                                ctx.lineWidth = w; ctx.lineCap = "round"; ctx.lineJoin = "round";
                                if (kind === "blur") {
                                    ctx.fillStyle = Qt.rgba(0.5, 0.5, 0.5, 0.75);
                                    ctx.fillRect(Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]));
                                } else if (kind === "box") {
                                    ctx.strokeRect(Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]));
                                } else if (kind === "text") {
                                    ctx.font = Math.max(12, w * 5) + "px sans-serif";
                                    ctx.fillText(words || "", a[0], a[1]);
                                } else {
                                    if (kind === "highlight") { ctx.globalAlpha = 0.4; ctx.lineWidth = w * 4; }
                                    ctx.beginPath(); ctx.moveTo(a[0], a[1]);
                                    const rest = win.twoPoint && live.length > 1 ? [b] : P.slice(1);
                                    for (const p of rest) ctx.lineTo(p[0], p[1]);
                                    if (P.length === 1) ctx.lineTo(a[0] + 0.1, a[1]);
                                    ctx.stroke();
                                    if (kind === "arrow") {
                                        const ang = Math.atan2(b[1] - a[1], b[0] - a[0]), L = Math.max(10, w * 5);
                                        ctx.beginPath(); ctx.moveTo(b[0], b[1]);
                                        ctx.lineTo(b[0] - L * Math.cos(ang - 0.45), b[1] - L * Math.sin(ang - 0.45));
                                        ctx.lineTo(b[0] - L * Math.cos(ang + 0.45), b[1] - L * Math.sin(ang + 0.45));
                                        ctx.closePath(); ctx.fill();
                                    }
                                }
                                ctx.restore();
                            }
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                for (const st of win.strokes) mark(ctx, st.kind, st.color, st.size, st.points, st.text);
                                mark(ctx, win.tool, win.penColor, win.penSize, live, win.textInput);
                            }
                            Connections {
                                target: win
                                function onStrokesChanged() { annoCanvas.requestPaint(); }
                                function onPenColorChanged() { annoCanvas.requestPaint(); }
                                function onPenSizeChanged() { annoCanvas.requestPaint(); }
                                function onToolChanged() { annoCanvas.requestPaint(); }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: win.pdfAnnoMode
                                cursorShape: Qt.CrossCursor
                                property point start
                                onPressed: m => {
                                    start = mapToItem(annoCanvas, m.x, m.y);
                                    annoCanvas.live = [[start.x / annoCanvas.width, start.y / annoCanvas.height]];
                                }
                                onPositionChanged: m => {
                                    if (!(pressedButtons & Qt.LeftButton)) return;
                                    const p = mapToItem(annoCanvas, m.x, m.y);
                                    annoCanvas.live = annoCanvas.live.concat([[p.x / annoCanvas.width, p.y / annoCanvas.height]]);
                                    annoCanvas.requestPaint();
                                }
                                onReleased: {
                                    if (win.tool === "text") {
                                        if (win.textInput.trim()) win.addStroke(annoCanvas.live);
                                    } else {
                                        win.addStroke(annoCanvas.live);
                                    }
                                    annoCanvas.live = [];
                                    annoCanvas.requestPaint();
                                }
                            }
                        }
                        // Annotation toolbar: tools, colours, undo, save into PDF
                        Rectangle {
                            visible: win.pdfAnnoMode && PdfViewer.current !== ""
                            anchors { bottom: pageFlick.bottom; horizontalCenter: parent.horizontalCenter; margins: Theme.px(12) }
                            width: Math.min(720, pageFlick.width - 24)
                            implicitHeight: toolsCol.implicitHeight + 12
                            radius: Theme.px(10)
                            color: Theme.alpha(Theme.surface1, 0.96)
                            border.width: 1
                            border.color: Theme.border
                            ColumnLayout {
                                id: toolsCol
                                anchors { fill: parent; margins: Theme.px(6) }
                                spacing: Theme.px(4)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(3)
                                    Repeater {
                                        model: [
                                            { id: "pen", t: Tr.t("Pen") }, { id: "highlight", t: Tr.t("Highlight") },
                                            { id: "line", t: Tr.t("Line") }, { id: "arrow", t: Tr.t("Arrow") },
                                            { id: "box", t: Tr.t("Box") }, { id: "blur", t: Tr.t("Blur") },
                                            { id: "text", t: Tr.t("Text") }
                                        ]
                                        Choice {
                                            required property var modelData
                                            text: modelData.t
                                            selected: win.tool === modelData.id
                                            onClicked: { win.tool = modelData.id; PdfViewer.setZoom(1); }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Button { text: Tr.t("Undo"); flat: true; enabled: win.strokes.length > 0; onClicked: win.undoStroke() }
                                    Button { text: Tr.t("Clear"); flat: true; enabled: win.strokes.length > 0; onClicked: win.clearMarks() }
                                    Button { text: Tr.t("Done"); flat: true; onClicked: { win.pdfAnnoMode = false; win.strokes = []; } }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: win.tool === "text"
                                    TextField {
                                        Layout.fillWidth: true
                                        placeholder: Tr.t("Text to place on the page, then drag on it")
                                        text: win.textInput
                                        onTextChanged: win.textInput = text
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(4)
                                    Text { text: Tr.t("Colour"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                                    Repeater {
                                        model: ["#e5484d", "#f5d90a", "#46a758", "#0091ff", "#ffffff"]
                                        Rectangle {
                                            required property string modelData
                                            width: Theme.px(18); height: Theme.px(18); radius: Theme.px(9)
                                            color: modelData
                                            border.width: win.penColor === modelData ? 2 : 0
                                            border.color: Theme.accent
                                            MouseArea { anchors.fill: parent; onClicked: win.penColor = modelData }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text { text: Tr.t("Size"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                                    Repeater {
                                        model: [0.005, 0.008, 0.014]
                                        Choice {
                                            required property real modelData
                                            text: modelData === 0.005 ? Tr.t("Fine") : modelData === 0.008 ? Tr.t("Medium") : Tr.t("Thick")
                                            selected: Math.abs(win.penSize - modelData) < 0.0001
                                            onClicked: win.penSize = modelData
                                        }
                                    }
                                    Button {
                                        text: Tr.t("Save into PDF")
                                        kind: "primary"
                                        enabled: win.strokes.length > 0
                                        onClicked: win.markPage()
                                    }
                                }
                            }
                        }
                        BusyNote {
                            visible: PdfViewer.loading
                            anchors.centerIn: parent
                            note: Tr.t("Rendering pages…")
                        }
                        // a PDF with a password: asked for here
                        ColumnLayout {
                            visible: PdfViewer.needsPassword
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 40, Theme.px(340))
                            spacing: Theme.px(8)
                            onVisibleChanged: if (visible) { pdfPass.text = ""; pdfPass.input.forceActiveFocus(); }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                text: Tr.t("This PDF is locked. Its password opens it.")
                                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale
                            }
                            TextField { id: pdfPass; Layout.fillWidth: true; secret: true; placeholderText: Tr.t("Password"); onAccepted: PdfViewer.unlockWith(text) }
                            Text {
                                visible: PdfViewer.passwordError !== ""
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: PdfViewer.passwordError
                                color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                            }
                            Button { Layout.alignment: Qt.AlignHCenter; kind: "primary"; text: Tr.t("Unlock"); enabled: pdfPass.text !== ""; onClicked: PdfViewer.unlockWith(pdfPass.text) }
                        }
                        ColumnLayout {
                            visible: !PdfViewer.loading && PdfViewer.current === "" && !PdfViewer.needsPassword
                            anchors.centerIn: parent
                            width: Math.max(Theme.px(120), Math.min(parent.width - Theme.px(40), Theme.px(300)))
                            spacing: Theme.px(8)
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                text: PdfViewer.error !== "" ? PdfViewer.error : Tr.t("No pages yet")
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(13) * Theme.fontScale
                            }
                            Button {
                                Layout.alignment: Qt.AlignHCenter
                                text: Tr.t("Open")
                                onClicked: win.pick()
                            }
                        }
                    }

                    // continuous scroll: every rendered page, one under the other
                    Flickable {
                        id: contFlick
                        visible: PdfViewer.continuous
                        anchors.fill: parent
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: contCol.width
                        contentHeight: contCol.height
                        Column {
                            id: contCol
                            spacing: Theme.px(8)
                            x: Theme.px(8)
                            width: Math.max(contFlick.width - Theme.px(16), 0)
                            Repeater {
                                model: PdfViewer.pages
                                Image {
                                    required property var modelData
                                    required property int index
                                    width: Theme.px(640)
                                    height: Theme.px(800)
                                    x: 8
                                    source: "file://" + PdfViewer.shownPage(modelData).split("/").map(encodeURIComponent).join("/")
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    cache: false
                                    asynchronous: true
                                    sourceSize: Qt.size(1280, 1600)
                                    rotation: PdfViewer.rotation
                                }
                            }
                        }
                    }
                }

                // the form's fields, one control each; the copy is saved beside the PDF
                Rectangle {
                    visible: PdfViewer.formShown
                    Layout.preferredWidth: Theme.px(280)
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        contentHeight: formCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: formCol
                            width: parent.width
                            spacing: Theme.px(8)
                            SectionTitle { Layout.fillWidth: true; text: Tr.t("Fill in") }
                            Repeater {
                                model: PdfViewer.formFields
                                ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Theme.px(3)
                                    Text {
                                        visible: modelData.type !== "checkbox"
                                        text: modelData.label.replace(/_/g, " ")
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        label: modelData.name || Tr.t("Value")
                                        visible: modelData.type === "text"
                                        text: String(PdfViewer.fieldValue(modelData))
                                        onTextChanged: if (visible && text !== String(PdfViewer.fieldValue(modelData))) PdfViewer.setField(modelData.name, text)
                                    }
                                    SwitchRow {
                                        Layout.fillWidth: true
                                        visible: modelData.type === "checkbox"
                                        text: modelData.label.replace(/_/g, " ")
                                        checked: PdfViewer.fieldValue(modelData) === true
                                        onToggled: on => PdfViewer.setField(modelData.name, on)
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        visible: modelData.type === "choice"
                                        spacing: Theme.px(6)
                                        Repeater {
                                            model: modelData.options
                                            Choice {
                                                required property string modelData
                                                text: modelData
                                                selected: PdfViewer.fieldValue(parent.parent.modelData) === modelData
                                                onClicked: PdfViewer.setField(parent.parent.modelData.name, modelData)
                                            }
                                        }
                                    }
                                    // radio groups: many widgets, one field name;
                                    // pdfform.py exposes the states as options
                                    Flow {
                                        Layout.fillWidth: true
                                        visible: modelData.type === "radio" && modelData.options.length > 0
                                        spacing: Theme.px(6)
                                        Repeater {
                                            model: modelData.options
                                            Choice {
                                                required property string modelData
                                                text: modelData
                                                selected: PdfViewer.fieldValue(parent.parent.modelData) === modelData
                                                onClicked: PdfViewer.setField(parent.parent.modelData.name, modelData)
                                            }
                                        }
                                    }
                                }
                            }
                            Button { Layout.fillWidth: true; kind: "primary"; text: Tr.t("Save a filled copy"); onClicked: PdfViewer.saveForm() }
                            Text {
                                Layout.fillWidth: true
                                visible: PdfViewer.formSaved !== "" || PdfViewer.formError !== ""
                                text: PdfViewer.formError !== "" ? PdfViewer.formError : Tr.t("Saved as %1", PdfViewer.formSaved.split("/").pop())
                                color: PdfViewer.formError !== "" ? Theme.danger : Theme.dim
                                wrapMode: Text.Wrap
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                            Button { visible: PdfViewer.formSaved !== ""; flat: true; text: Tr.t("Open the filled copy"); onClicked: PdfViewer.open(PdfViewer.formSaved) }
                        }
                    }
                }

                // ---- bookmarks / links / attachments / annotations -----------------
                Rectangle {
                    visible: win.extraPanel !== ""
                    Layout.preferredWidth: Theme.px(280)
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: win.extraPanel === "bookmarks" ? Tr.t("Your bookmarks")
                                    : win.extraPanel === "links" ? Tr.t("Links")
                                    : win.extraPanel === "attachments" ? Tr.t("Attachments") : Tr.t("Annotations")
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                                font.weight: Font.DemiBold
                            }
                            IconButton { icon: "window-close"; size: Theme.px(22); tip: Tr.t("Close"); onClicked: win.extraPanel = "" }
                        }
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentHeight: extrasCol.implicitHeight
                            ColumnLayout {
                                id: extrasCol
                                width: parent.width
                                spacing: Theme.px(6)

                                // the reader's own bookmarks, kept by document md5
                                ColumnLayout {
                                    visible: win.extraPanel === "bookmarks"
                                    Layout.fillWidth: true
                                    spacing: Theme.px(6)
                                    TextField {
                                        id: bookmarkTitle
                                        Layout.fillWidth: true
                                        placeholder: Tr.t("Bookmark name")
                                        label: Tr.t("Bookmark name")
                                        text: Tr.t("Page %1", PdfViewer.page + 1)
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        text: Tr.t("Bookmark page %1", PdfViewer.page + 1)
                                        onClicked: PdfViewer.addBookmark(PdfViewer.page, bookmarkTitle.text)
                                    }
                                    Repeater {
                                        model: PdfViewer.userBookmarks
                                        RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title + "  ·  " + (modelData.page + 1)
                                                color: Theme.text
                                                font.family: Theme.font
                                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                                elide: Text.ElideRight
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: PdfViewer.goTo(modelData.page) }
                                                Accessible.role: Accessible.Button
                                                Accessible.name: Tr.t("Bookmark page %1", modelData.page + 1) + " · " + modelData.title
                                                KeyFocus { onActivated: PdfViewer.goTo(modelData.page) }
                                            }
                                            IconButton { icon: "list-remove"; size: Theme.px(20); tip: Tr.t("Remove bookmark"); onClicked: PdfViewer.removeBookmark(modelData.page) }
                                        }
                                    }
                                }

                                // links from the PDF itself
                                Repeater {
                                    model: win.extraPanel === "links" ? PdfViewer.pdfLinks : []
                                    Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: Theme.px(30)
                                        radius: Theme.px(8)
                                        color: linkArea.containsMouse ? Theme.hover : "transparent"
                                        Text {
                                            anchors.fill: parent
                                            anchors.margins: Theme.px(6)
                                            text: modelData.kind === "uri" ? modelData.uri
                                                : modelData.kind === "goto" ? Tr.t("Page %1", modelData.target) : modelData.name
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(11) * Theme.fontScale
                                            elide: Text.ElideMiddle
                                        }
                                        MouseArea { id: linkArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: PdfViewer.followLink(modelData) }
                                    }
                                }

                                // embedded files
                                Repeater {
                                    model: win.extraPanel === "attachments" ? PdfViewer.attachments : []
                                    RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name + "  ·  " + modelData.size
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(11) * Theme.fontScale
                                            elide: Text.ElideMiddle
                                        }
                                        Button { flat: true; text: Tr.t("Save"); onClicked: win.saveAttachment(modelData.index, modelData.name) }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: win.extraPanel === "attachments" && PdfViewer.attachmentNote !== ""
                                    text: PdfViewer.attachmentNote
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(10) * Theme.fontScale
                                    wrapMode: Text.Wrap
                                }

                                // existing markup, read back from the PDF
                                Repeater {
                                    model: win.extraPanel === "annotations" ? PdfViewer.annotations : []
                                    Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: annText.implicitHeight + Theme.px(12)
                                        radius: Theme.px(8)
                                        color: Theme.surface2
                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: Theme.px(6)
                                            Text {
                                                id: annText
                                                width: parent.width
                                                text: modelData.type + "  ·  " + Tr.t("page %1", modelData.page + 1)
                                                    + (modelData.title ? "  ·  " + modelData.title : "")
                                                    + (modelData.content ? "\n" + modelData.content : "")
                                                color: Theme.text
                                                font.family: Theme.font
                                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                                wrapMode: Text.Wrap
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: PdfViewer.goTo(modelData.page) }
                                                Accessible.role: Accessible.Button
                                                Accessible.name: modelData.type + " · " + Tr.t("page %1", modelData.page + 1)
                                                KeyFocus { onActivated: PdfViewer.goTo(modelData.page) }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: win.extraPanel === "links" && PdfViewer.pdfLinks.length === 0
                                    text: Tr.t("No links in this document")
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: win.extraPanel === "attachments" && PdfViewer.attachments.length === 0
                                    text: Tr.t("No embedded files")
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: win.extraPanel === "annotations" && PdfViewer.annotations.length === 0
                                    text: Tr.t("No annotations yet — mark up a page to add one")
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
                            }
                        }
                    }
                }
            }

            // fit / continuous / rotation toolbar
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                IconButton { icon: "zoom-fit-best"; size: Theme.px(28); tip: Tr.t("Fit page (F)"); on: PdfViewer.fitMode === "page"; onClicked: PdfViewer.setFit("page") }
                IconButton { icon: "view-fullscreen"; size: Theme.px(28); tip: Tr.t("Fit width (W)"); on: PdfViewer.fitMode === "width"; onClicked: PdfViewer.setFit("width") }
                IconButton { icon: "document-save"; size: Theme.px(28); tip: Tr.t("Actual size"); on: PdfViewer.fitMode === "actual"; onClicked: PdfViewer.setFit("actual") }
                IconButton { icon: "view-dual"; size: Theme.px(28); tip: Tr.t("Continuous scroll"); on: PdfViewer.continuous; onClicked: PdfViewer.toggleContinuous() }
                IconButton { icon: "view-pages-facing"; size: Theme.px(28); tip: Tr.t("Facing pages (two-page spread)"); on: PdfViewer.facing; onClicked: PdfViewer.toggleFacing() }
                IconButton { icon: "object-rotate-right"; size: Theme.px(28); tip: Tr.t("Rotate right (R)"); onClicked: PdfViewer.rotate() }
                IconButton { icon: "object-rotate-left"; size: Theme.px(28); tip: Tr.t("Rotate left"); onClicked: PdfViewer.rotateCCW() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: (PdfViewer.spreadLabel !== "" ? PdfViewer.spreadLabel + "  ·  " : "") + Tr.t("← → to turn pages · Esc closes")
                        + (PdfViewer.rotation !== 0 ? "  ·  " + PdfViewer.rotation + "°" : "")
                        + (PdfViewer.facingActive ? "  ·  " + Tr.t("facing pages") : "")
                        + (PdfViewer.fitMode === "width" ? "  ·  " + Tr.t("fit width") : PdfViewer.fitMode === "actual" ? "  ·  " + Tr.t("actual size") : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    elide: Text.ElideRight
                }
            }
        }
    }
}
