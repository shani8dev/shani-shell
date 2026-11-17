// The whiteboard (docs/FORM-FACTORS.md, the classroom board): a full-screen
// surface to write on with a pen, a finger or the mouse - several fingers at
// once, as when two children write on the board together - in pages, saved as
// one PDF in Documents/Whiteboards. The controls are along the bottom, within
// a child's reach on a 75" board; nothing needed is at the top.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import qs.Common
import qs.Services
import "../../Common/Pen.js" as Pen

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    visible: Ui.whiteboard
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-whiteboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // pages: [[{ color, width, points: [{x, y}] }]]
    property var pages: [[]]
    property int page: 0
    property color ink: inks[0]
    property real thickness: Theme.px(4)
    property bool erasing: false
    readonly property var inks: ["#1f2328", "#d1242f", "#0969da", "#1a7f37", "#bf8700", "#8250df"]
    readonly property color paper: Settings.data.whiteboardDark ? "#1d2a24" : "#fbfbf8"
    property int saves: 0                 // the tests
    property string savedTo: ""
    function counted() { let n = 0; for (let i = 0; i < pages.length; i++) n += pages[i].length; Ui.whiteboardStrokes = n; }
    onPageChanged: Ui.whiteboardPage = page
    onVisibleChanged: if (visible) Qt.callLater(() => keys.forceActiveFocus())

    function strokes() { return pages[page] || []; }
    // a stroke from elsewhere than a finger (the tests; a pen app later): as if drawn
    function addStroke(points) { setStrokes(strokes().concat([{ color: String(ink), width: thickness, points: points }])); }
    function setStrokes(s) { const p = pages.slice(); p[page] = s; pages = p; counted(); canvas.requestPaint(); }
    function undo() { setStrokes(strokes().slice(0, -1)); }
    function clearPage() { setStrokes([]); }
    function newPage() { const p = pages.slice(); p.splice(page + 1, 0, []); pages = p; page = page + 1; canvas.requestPaint(); }
    function go(d) { page = Math.max(0, Math.min(pages.length - 1, page + d)); canvas.requestPaint(); }
    // a stroke the eraser touched goes whole (the board's eraser, not a pixel rubber)
    function eraseAt(x, y) {
        const r = Theme.px(18);
        const keep = strokes().filter(s => !s.points.some(p => Math.abs(p.x - x) < r && Math.abs(p.y - y) < r));
        if (keep.length !== strokes().length) setStrokes(keep);
    }

    // saving: each page drawn on the canvas in turn and kept as a PNG, then the
    // PNGs made one PDF (PyMuPDF, already the shell's)
    property int saving: -1
    property string saveDir: ""
    function save() {
        if (saving >= 0) return;
        saveDir = "/tmp/shani-whiteboard-" + Date.now();
        Quickshell.execDetached(["mkdir", "-p", saveDir]);
        saving = 0;
        shownPage = page;
        page = 0;
        canvas.requestPaint();
        saveTick.restart();
    }
    property int shownPage: 0
    Timer {
        id: saveTick
        interval: 120
        onTriggered: {
            canvas.save(win.saveDir + "/" + String(win.saving).padStart(3, "0") + ".png");
            if (win.saving < win.pages.length - 1) {
                win.saving++;
                win.page = win.saving;
                canvas.requestPaint();
                saveTick.restart();
            } else {
                win.page = win.shownPage;
                canvas.requestPaint();
                makePdf.command = ["python3", "-c", win.pdfScript, win.saveDir, (Quickshell.env("HOME") || "/tmp") + "/Documents/Whiteboards"];
                makePdf.running = true;
            }
        }
    }
    readonly property string pdfScript: "import sys, os, glob, time, shutil, fitz\n" +
        "src, out = sys.argv[1], sys.argv[2]\n" +
        "os.makedirs(out, exist_ok=True)\n" +
        "doc = fitz.open()\n" +
        "for png in sorted(glob.glob(os.path.join(src, '*.png'))):\n" +
        "    img = fitz.open(png); rect = img[0].rect\n" +
        "    page = doc.new_page(width=rect.width, height=rect.height)\n" +
        "    page.insert_image(rect, filename=png)\n" +
        "path = os.path.join(out, time.strftime('Whiteboard %Y-%m-%d %H-%M-%S.pdf'))\n" +
        "doc.save(path); shutil.rmtree(src, ignore_errors=True); print(path)\n"
    Process {
        id: makePdf
        stdout: StdioCollector {
            onStreamFinished: {
                win.saving = -1;
                const p = text.trim();
                if (p === "") return;
                win.savedTo = p;
                win.saves++;
                Ui.whiteboardSaved = p;
                Quickshell.execDetached(["notify-send", "-a", Tr.t("Whiteboard"), "-i", "x-office-document",
                                         Tr.t("Whiteboard saved"), p.split("/").pop()]);
            }
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) Ui.whiteboard = false;
            else if (e.key === Qt.Key_Z && (e.modifiers & Qt.ControlModifier)) win.undo();
            else if (e.key === Qt.Key_S && (e.modifiers & Qt.ControlModifier)) win.save();
            else if (e.key === Qt.Key_PageDown || e.key === Qt.Key_Right) win.go(1);
            else if (e.key === Qt.Key_PageUp || e.key === Qt.Key_Left) win.go(-1);
            else return;
            e.accepted = true;
        }

        Rectangle { anchors.fill: parent; color: win.paper }

        Canvas {
            id: canvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = win.paper;
                ctx.fillRect(0, 0, width, height);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                for (const s of win.strokes().concat(Object.values(live.drawing)).concat(pen.stroke ? [pen.stroke] : [])) {
                    if (!s.points.length) continue;
                    ctx.strokeStyle = s.color;
                    // a pen's line: each piece as wide as it was pressed
                    if (s.pen && s.points.length > 1) {
                        for (let i = 1; i < s.points.length; i++) {
                            ctx.lineWidth = s.points[i].w || s.width;
                            ctx.beginPath();
                            ctx.moveTo(s.points[i - 1].x, s.points[i - 1].y);
                            ctx.lineTo(s.points[i].x, s.points[i].y);
                            ctx.stroke();
                        }
                        continue;
                    }
                    ctx.lineWidth = s.width;
                    ctx.beginPath();
                    ctx.moveTo(s.points[0].x, s.points[0].y);
                    for (const p of s.points) ctx.lineTo(p.x, p.y);
                    if (s.points.length === 1) ctx.lineTo(s.points[0].x + 0.1, s.points[0].y);
                    ctx.stroke();
                }
            }
        }

        // the pen: its own line, as wide as it is pressed; turned over (its eraser
        // end) or with its side button held, it erases. While it is on the board
        // or just above it, touches are the hand holding it, not writing.
        HoverHandler { id: penNear; acceptedDevices: PointerDevice.Stylus }
        PointHandler {
            id: pen
            target: null
            enabled: win.saving < 0
            acceptedDevices: PointerDevice.Stylus
            acceptedPointerTypes: PointerDevice.Pen
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property var stroke: null
            readonly property bool erasing: win.erasing || (point.pressedButtons & Qt.RightButton)
            onActiveChanged: {
                if (active && !erasing) {
                    stroke = { color: String(win.ink), width: win.thickness, pen: true,
                               points: [{ x: point.position.x, y: point.position.y, w: Pen.width(win.thickness, point.pressure, true) }] };
                } else if (!active && stroke) {
                    const s = stroke;
                    stroke = null;
                    if (s.points.length) win.setStrokes(win.strokes().concat([s]));
                }
                canvas.requestPaint();
            }
            onPointChanged: {
                if (!active) return;
                if (erasing) { win.eraseAt(point.position.x, point.position.y); return; }
                if (stroke) {
                    stroke.points.push({ x: point.position.x, y: point.position.y, w: Pen.width(win.thickness, point.pressure, true) });
                    canvas.requestPaint();
                }
            }
        }
        PointHandler {
            id: penEraser
            target: null
            enabled: win.saving < 0
            acceptedDevices: PointerDevice.Stylus
            acceptedPointerTypes: PointerDevice.Eraser
            onPointChanged: if (active) win.eraseAt(point.position.x, point.position.y)
        }

        // every finger (and the mouse) its own stroke, all at once; a palm, and
        // any touch while the pen is near, is left alone
        MultiPointTouchArea {
            id: live
            anchors { fill: parent; bottomMargin: bar.height + Theme.px(24) }
            mouseEnabled: true
            maximumTouchPoints: 10
            property var drawing: ({})       // touch point id -> stroke being drawn
            enabled: win.saving < 0
            readonly property bool penAround: penNear.hovered || pen.active || penEraser.active
            onPressed: pts => {
                const d = Object.assign({}, drawing);
                for (const p of pts) {
                    if (Pen.rejectTouch(penAround, p.ellipseDiameters.width, p.ellipseDiameters.height, Theme.px(60))) continue;
                    if (win.erasing) { win.eraseAt(p.x, p.y); continue; }
                    d[p.pointId] = { color: String(win.ink), width: win.thickness, points: [{ x: p.x, y: p.y }] };
                }
                drawing = d;
                canvas.requestPaint();
            }
            onUpdated: pts => {
                for (const p of pts) {
                    if (win.erasing) { win.eraseAt(p.x, p.y); continue; }
                    const s = drawing[p.pointId];
                    if (s) s.points.push({ x: p.x, y: p.y });
                }
                canvas.requestPaint();
            }
            onReleased: pts => {
                const d = Object.assign({}, drawing);
                const done = [];
                for (const p of pts)
                    if (d[p.pointId]) { done.push(d[p.pointId]); delete d[p.pointId]; }
                drawing = d;
                if (done.length) win.setStrokes(win.strokes().concat(done));
            }
        }

        // the controls, along the bottom: inks, sizes, eraser, undo, pages, save, close
        Rectangle {
            id: bar
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.px(16) }
            width: row.implicitWidth + Theme.px(24)
            height: Theme.px(64)
            radius: height / 2
            color: Theme.alpha(Theme.bg, 0.92)
            border.color: Theme.border
            Row {
                id: row
                anchors.centerIn: parent
                spacing: Theme.px(10)
                Repeater {
                    model: win.inks
                    delegate: Rectangle {
                        required property string modelData
                        width: Theme.px(40); height: width; radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData
                        border.width: !win.erasing && String(win.ink) === Qt.color(modelData).toString() ? Theme.px(4) : Theme.px(1)
                        border.color: Theme.accent
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("Ink")
                        MouseArea { anchors.fill: parent; onClicked: { win.ink = parent.modelData; win.erasing = false; } }
                    }
                }
                Rectangle { width: 1; height: Theme.px(36); color: Theme.border; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: [3, 6, 12]
                    delegate: Rectangle {
                        required property int modelData
                        width: Theme.px(40); height: width; radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: Math.abs(win.thickness - Theme.px(modelData)) < 0.5 ? Theme.accentSoft : "transparent"
                        Rectangle { anchors.centerIn: parent; width: Theme.px(parent.modelData) + 2; height: width; radius: width / 2; color: Theme.text }
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("Line width")
                        MouseArea { anchors.fill: parent; onClicked: win.thickness = Theme.px(parent.modelData) }
                    }
                }
                Rectangle { width: 1; height: Theme.px(36); color: Theme.border; anchors.verticalCenter: parent.verticalCenter }
                IconButton { icon: "draw-eraser"; size: Theme.px(40); anchors.verticalCenter: parent.verticalCenter; Accessible.name: Tr.t("Eraser"); on: win.erasing; onClicked: win.erasing = !win.erasing }
                IconButton { icon: "edit-undo"; size: Theme.px(40); anchors.verticalCenter: parent.verticalCenter; Accessible.name: Tr.t("Undo"); onClicked: win.undo() }
                IconButton { icon: "edit-clear-all"; size: Theme.px(40); anchors.verticalCenter: parent.verticalCenter; Accessible.name: Tr.t("Clear the page"); onClicked: win.clearPage() }
                Rectangle { width: 1; height: Theme.px(36); color: Theme.border; anchors.verticalCenter: parent.verticalCenter }
                IconButton { icon: "go-previous"; size: Theme.px(40); anchors.verticalCenter: parent.verticalCenter; Accessible.name: Tr.t("Previous page"); enabled: win.page > 0; onClicked: win.go(-1) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (win.page + 1) + " / " + win.pages.length
                    color: Theme.text
                    font.pixelSize: Theme.px(15) * Theme.fontScale
                }
                IconButton { icon: "go-next"; size: Theme.px(40); anchors.verticalCenter: parent.verticalCenter; Accessible.name: Tr.t("Next page"); enabled: win.page < win.pages.length - 1; onClicked: win.go(1) }
                IconButton { icon: "document-new"; size: Theme.px(40); anchors.verticalCenter: parent.verticalCenter; Accessible.name: Tr.t("New page"); onClicked: win.newPage() }
                Rectangle { width: 1; height: Theme.px(36); color: Theme.border; anchors.verticalCenter: parent.verticalCenter }
                IconButton { icon: "document-save"; size: Theme.px(40); anchors.verticalCenter: parent.verticalCenter; Accessible.name: Tr.t("Save as PDF"); onClicked: win.save() }
                IconButton { icon: "window-close"; size: Theme.px(40); anchors.verticalCenter: parent.verticalCenter; Accessible.name: Tr.t("Close the whiteboard"); onClicked: Ui.whiteboard = false }
            }
        }
    }
}
