// A picture, full size in the shell (Viewer) — Loupe parity: zoom to cursor
// (wheel), fit / 100% / 200%, rotate + flip, slideshow, thumbnail strip,
// EXIF-aware rotation (applied by the service), batch grid mode, copy path,
// open-with, delete-to-trash. ← → through its folder, Esc or click to close.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/Gestures.js" as Hold

AppWindow {
    id: win
    appName: "Image Viewer"
    visible: Viewer.shown
    onGone: Viewer.close()
    margins: 0
    // full screen: the shell header and every toolbar row step aside; the Exit
    // button below stays put (CoreImage's full-screen has the same way out)
    header: !immersive
    implicitWidth: Theme.px(920)
    implicitHeight: Theme.px(720)
    // blur behind the card, as on every shell surface (ext-background-effect)

    property bool immersive: false
    property string saveAsTarget: ""
    property string note: ""
    property int dragStartX: 0
    property int dragStartY: 0
    property real dragPanX: 0
    property real dragPanY: 0
    // shortcut: hand-rolled two-tap kept — shared by Del key + toolbar IconButton; external tests pin this shape
    property string trashConfirm: ""
    // one tap arms, the next trashes — the toolbar button and Del share it
    function askTrash() {
        if (trashConfirm) { Viewer.trash(); trashConfirm = ""; }
        else { trashConfirm = "trash"; trashConfirmTimer.restart(); }
    }
    Timer { id: trashConfirmTimer; interval: 4000; onTriggered: win.trashConfirm = "" }

    // jump from the picture to its folder in Files, with the picture chosen;
    // a URL is not a file on disk, so there is nothing to show
    function reveal(path) {
        const p = String(path || ""); if (!p.startsWith("/")) return;
        const at = p.lastIndexOf("/"); Files.show(at === 0 ? "/" : p.substring(0, at)); Files.select(p, "single");
    }

    // ---- Save as: let the person name the copy (CoreImage's Save As). The edit
    // service still writes its "(edited)" file; move that one file to the picked
    // name — no second render and no change to the service's shared API.
    function saveAs() {
        if (!Viewer.file || Viewer.saving) return;
        const ext = Viewer.name.indexOf(".") >= 0 ? Viewer.name.split(".").pop() : "png";
        FilePicker.open({
            mode: "save",
            title: Tr.t("Save image as"),
            defaultName: Viewer.name.replace(/\.[^.]+$/, "") + " (edited)." + ext,
            startPath: Viewer.file.substring(0, Viewer.file.lastIndexOf("/")),
            filters: [ext],
            onPicked: paths => {
                if (!paths || !paths.length) return;
                const to = paths[0];
                if (to === Viewer.file) { win.note = Tr.t("Choose a different name to save a copy"); return; }
                win.saveAsTarget = to;
                Viewer.saveEdit("copy");
            }
        });
    }
    Process {
        id: saveAsMove
        onExited: code => {
            const to = win.saveAsTarget;
            win.saveAsTarget = "";
            win.note = code === 0 ? Tr.t("Saved as %1", to.split("/").pop()) : Tr.t("Could not save as %1", to.split("/").pop());
            if (code === 0) Viewer.open(to);
        }
    }
    Connections {
        target: Viewer
        function onSavedChanged() {
            if (!win.saveAsTarget || !Viewer.saved) return;
            saveAsMove.command = ["mv", "-f", "--", Viewer.saved, win.saveAsTarget];
            saveAsMove.running = true;
        }
        function onLastActionChanged() {
            if (Viewer.lastAction === "edit failed") win.saveAsTarget = "";
        }
    }
    Rectangle {
        id: noteToast
        z: 20
        visible: win.note !== ""
        anchors { bottom: parent.bottom; right: parent.right; margins: Theme.px(12) }
        implicitWidth: noteText.implicitWidth + Theme.px(20)
        implicitHeight: noteText.implicitHeight + Theme.px(12)
        radius: Theme.px(8)
        color: Theme.alpha(Theme.surface1, 0.96)
        border.width: 1
        border.color: Theme.border
        Text { id: noteText; anchors.centerIn: parent; text: win.note; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
    }
    Timer { interval: 4000; onTriggered: win.note = ""; running: noteToast.visible }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: {
            if (win.immersive) { win.immersive = false; return; }
            if (Viewer.textAt !== null) Viewer.textAt = null;
            else if (Viewer.editing) Viewer.cancelEdit();
            else Viewer.close();
        }
        Keys.onRightPressed: Viewer.next()
        Keys.onLeftPressed: Viewer.prev()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_F11) { win.immersive = !win.immersive; e.accepted = true; return; }
            if (e.key === Qt.Key_Home) { if (Viewer.list.length) Viewer.goToIndex(0); e.accepted = true; return; }
            if (e.key === Qt.Key_End) { if (Viewer.list.length) Viewer.goToIndex(Viewer.list.length - 1); e.accepted = true; return; }
            if (e.key === Qt.Key_R && (e.modifiers & Qt.ShiftModifier)) Viewer.rotateCCW();
            else if (e.key === Qt.Key_R) Viewer.rotate();
            else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) Viewer.zoomIn();
            else if (e.key === Qt.Key_Minus) Viewer.zoomOut();
            else if (e.key === Qt.Key_0) Viewer.zoomReset();
            else if (e.key === Qt.Key_F) Viewer.zoomFit();
            else if (e.key === Qt.Key_1) Viewer.zoomActual();
            else if (e.key === Qt.Key_2) Viewer.zoom200();
            else if (e.key === Qt.Key_H) Viewer.toggleFlipH();
            else if (e.key === Qt.Key_V) Viewer.toggleFlipV();
            else if (e.key === Qt.Key_S) Viewer.toggleSlideshow();
            else if (e.key === Qt.Key_G) Viewer.toggleGrid();
            else if (e.key === Qt.Key_T) Viewer.toggleThumbs();
            else if (e.key === Qt.Key_C) Viewer.copyPath();
            else if (e.key === Qt.Key_L && (e.modifiers & Qt.ControlModifier)) win.reveal(Viewer.file);
            else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) win.askTrash();
            else if (e.key === Qt.Key_O) Viewer.openWith();
            else if (e.key === Qt.Key_E) { if (Viewer.editing) Viewer.cancelEdit(); else Viewer.startEdit(); }
        }
    }
    Item {
        id: blurCard
        anchors.fill: parent
        MouseArea { anchors.fill: parent; objectName: "nav:pointer" }       // clicks inside do not close it
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(8)

            RowLayout {
                visible: !win.immersive
                Layout.fillWidth: true
                spacing: Theme.px(6)
                IconButton { icon: "go-previous"; size: Theme.px(28); tip: Tr.t("Previous (←)"); onClicked: Viewer.prev() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Viewer.name + (Viewer.position !== "" ? "  ·  " + Viewer.position : "")
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-next"; size: Theme.px(28); tip: Tr.t("Next (→)"); onClicked: Viewer.next() }
            }

            // main stage: single image, or the batch grid
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true

                // an AnimatedImage is an Image that also plays (GIF, animated WebP, APNG -
                // Loupe plays them); a still picture is one frame
                AnimatedImage {
                    id: mainImage
                    playing: Viewer.file !== "" && !Viewer.editing
                    visible: !Viewer.gridMode
                    width: parent.width
                    height: parent.height
                    x: Viewer.panX
                    y: Viewer.panY
                    source: Viewer.shownFile !== "" ? "file://" + Viewer.shownFile.split("/").map(encodeURIComponent).join("/") : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    cache: false
                    // turned a quarter, the fitted picture's sides swap: scaled down so it
                    // still fits (it overflowed the box before)
                    readonly property bool turned: Viewer.rotation % 180 !== 0
                    readonly property real fitTurned: turned && paintedWidth > 0 && paintedHeight > 0
                        ? Math.min(1, width / paintedHeight, height / paintedWidth) : 1
                    scale: Viewer.zoom * fitTurned
                    rotation: Viewer.rotation
                    transformOrigin: Item.Center
                    transform: Scale {
                        xScale: Viewer.flipH ? -1 : 1
                        yScale: Viewer.flipV ? -1 : 1
                        origin.x: mainImage.width / 2
                        origin.y: mainImage.height / 2
                    }
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "Picture: " + Viewer.name
                    Binding { target: Viewer; property: "frames"; value: mainImage.frameCount }
                    Binding { target: Viewer; property: "loadStatus"; value: mainImage.status === Image.Ready ? "ready" : mainImage.status === Image.Error ? "error" : "loading" }
                }
                // editing: the crop over the picture as shown (turned: its sides swap)
                Item {
                    id: cropArea
                    visible: Viewer.editing && !Viewer.gridMode
                    readonly property bool turned: Viewer.rotation % 180 !== 0
                    width: (turned ? mainImage.paintedHeight : mainImage.paintedWidth) * mainImage.fitTurned
                    height: (turned ? mainImage.paintedWidth : mainImage.paintedHeight) * mainImage.fitTurned
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2
                    readonly property real shownRatio: height > 0 ? width / height : 1
                    // fixed aspect: a corner moves the width, the height follows
                    function wantRatio() {
                        const a = Viewer.cropAspect;
                        return a === "square" ? 1 : a === "4:3" ? 4 / 3 : a === "16:9" ? 16 / 9 : a === "original" ? shownRatio : 0;
                    }
                    // the dimmed outside
                    Rectangle { x: 0; y: 0; width: parent.width; height: frame.y; color: "#99000000" }
                    Rectangle { x: 0; y: frame.y + frame.height; width: parent.width; height: parent.height - y; color: "#99000000" }
                    Rectangle { x: 0; y: frame.y; width: frame.x; height: frame.height; color: "#99000000" }
                    Rectangle { x: frame.x + frame.width; y: frame.y; width: parent.width - x; height: frame.height; color: "#99000000" }
                    Rectangle {
                        id: frame
                        x: Viewer.cropX * cropArea.width
                        y: Viewer.cropY * cropArea.height
                        width: Viewer.cropW * cropArea.width
                        height: Viewer.cropH * cropArea.height
                        color: "transparent"
                        border.width: 2
                        border.color: "white"
                        Accessible.role: Accessible.Graphic
                        Accessible.name: Tr.t("Crop")
                        // the body moves it
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: Theme.px(14)
                            cursorShape: Qt.SizeAllCursor
                            property point start
                            property real sx: 0
                            property real sy: 0
                            onPressed: m => { start = mapToItem(cropArea, m.x, m.y); sx = Viewer.cropX; sy = Viewer.cropY; }
                            onPositionChanged: m => {
                                const p = mapToItem(cropArea, m.x, m.y);
                                Viewer.setCrop(sx + (p.x - start.x) / cropArea.width, sy + (p.y - start.y) / cropArea.height, Viewer.cropW, Viewer.cropH);
                            }
                        }
                        // the corners size it (the opposite corner stays put)
                        Repeater {
                            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                            Rectangle {
                                required property var modelData
                                width: Theme.px(18); height: width; radius: width / 2
                                color: "white"
                                x: modelData[0] * frame.width - width / 2
                                y: modelData[1] * frame.height - height / 2
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -Theme.px(6)
                                    cursorShape: Qt.SizeFDiagCursor
                                    onPositionChanged: m => {
                                        const p = mapToItem(cropArea, m.x, m.y);
                                        const fx = Math.max(0, Math.min(1, p.x / cropArea.width)), fy = Math.max(0, Math.min(1, p.y / cropArea.height));
                                        // the fixed corner
                                        const ox = parent.modelData[0] ? Viewer.cropX : Viewer.cropX + Viewer.cropW;
                                        const oy = parent.modelData[1] ? Viewer.cropY : Viewer.cropY + Viewer.cropH;
                                        let w = Math.abs(fx - ox), h = Math.abs(fy - oy);
                                        const r = cropArea.wantRatio();
                                        if (r > 0) h = w * cropArea.width / (cropArea.height * r);
                                        const x = parent.modelData[0] ? ox : ox - w, y = parent.modelData[1] ? oy : oy - h;
                                        Viewer.setCrop(x, y, w, h);
                                    }
                                }
                            }
                        }
                    }
                }
                // markup: the strokes so far, and a pen while Draw is on (over the crop)
                Canvas {
                    id: inkCanvas
                    visible: Viewer.editing && !Viewer.gridMode
                    x: cropArea.x; y: cropArea.y; width: cropArea.width; height: cropArea.height
                    z: 2
                    property var live: []                    // the stroke being drawn
                    // each kind as imgedit.py will burn it in
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
                            ctx.beginPath();
                            ctx.moveTo(a[0], a[1]);
                            const pts2 = kind === "line" || kind === "arrow" ? [b] : P.slice(1);
                            for (const p of pts2) ctx.lineTo(p[0], p[1]);
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
                        for (const s of Viewer.strokes) mark(ctx, s.kind || "pen", s.color, s.size, s.points, s.text);
                        mark(ctx, Viewer.tool, Viewer.penColor, Viewer.penSize, Viewer.twoPoint && live.length > 1 ? [live[0], live[live.length - 1]] : live, "");
                    }
                    Connections { target: Viewer; function onStrokesChanged() { inkCanvas.requestPaint(); } }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    // the words, typed where the text tool was clicked
                    TextField {
                        visible: Viewer.textAt !== null
                        x: Viewer.textAt ? Math.min(Viewer.textAt[0] * parent.width, parent.width - width) : 0
                        y: Viewer.textAt ? Math.max(0, Viewer.textAt[1] * parent.height - height) : 0
                        z: 5
                        width: Theme.px(220)
                        placeholderText: Tr.t("Words, then Enter")
                        onVisibleChanged: if (visible) { text = ""; input.forceActiveFocus(); }
                        onAccepted: Viewer.addText(text)
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: Viewer.drawing && Viewer.textAt === null
                        cursorShape: Qt.CrossCursor
                        function at(m) { return [Math.max(0, Math.min(1, m.x / width)), Math.max(0, Math.min(1, m.y / height))]; }
                        onPressed: m => {
                            if (Viewer.tool === "text") { Viewer.textAt = at(m); return; }   // words typed where it was clicked
                            inkCanvas.live = [at(m)]; inkCanvas.requestPaint();
                        }
                        onPositionChanged: m => { inkCanvas.live = inkCanvas.live.concat([at(m)]); inkCanvas.requestPaint(); }
                        onReleased: { if (Viewer.tool !== "text") { Viewer.addStroke(inkCanvas.live); inkCanvas.live = []; } }
                    }
                }
                EmptyState {
                    visible: Viewer.file === ""
                    anchors.centerIn: parent
                    width: parent.width - Theme.px(32)
                    icon: "image-x-generic"
                    title: Tr.t("No picture")
                }

                // batch grid mode: the whole folder at once (Loupe's gallery)
                Flickable {
                    visible: Viewer.gridMode
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: grid.width
                    contentHeight: grid.height
                    Grid {
                        id: grid
                        columns: 4
                        spacing: Theme.px(8)
                        padding: Theme.px(8)
                        Repeater {
                            model: Viewer.list
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: Theme.px(180)
                                height: Theme.px(140)
                                radius: Theme.radiusSmall
                                color: index === Viewer.index ? Theme.alpha(Theme.accent, 0.22) : Theme.surface1
                                border.width: index === Viewer.index ? 2 : 0
                                border.color: Theme.accent
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(6)
                                    source: "file://" + modelData.split("/").map(encodeURIComponent).join("/")
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    cache: true
                                    asynchronous: true
                                    sourceSize: Qt.size(300, 300)
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottomMargin: Theme.px(4)
                                    text: String(index + 1)
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(10) * Theme.fontScale
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Viewer.goToIndex(index)
                                }
                                KeyFocus { name: String(modelData).split("/").pop(); onActivated: Viewer.goToIndex(index) }
                            }
                        }
                    }
                }

                // two fingers: zoom about the point between them, as the wheel does about the pointer
                PinchHandler {
                    target: null
                    enabled: !Viewer.gridMode
                    property real last: 1
                    onActiveChanged: last = 1
                    onActiveScaleChanged: {
                        const f = activeScale / last;
                        last = activeScale;
                        Viewer.zoomToCursor(centroid.position.x, centroid.position.y, f, parent.width, parent.height);
                    }
                }
                MouseArea {
                    objectName: "nav:keys"          // the picture: zoom, turn, next with the window's keys and the toolbar
                    visible: !Viewer.gridMode
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    // a finger has no right button: a long press turns the picture
                    property var held: Hold.state()
                    cursorShape: Viewer.zoom > 1.05 ? Qt.OpenHandCursor : Qt.ArrowCursor
                    onWheel: w => {
                        const f = w.angleDelta.y > 0 ? 1.2 : 1 / 1.2;
                        Viewer.zoomToCursor(w.x, w.y, f, width, height);
                    }
                    onPressed: m => {
                        Hold.press(held);
                        win.dragStartX = m.x;
                        win.dragStartY = m.y;
                        win.dragPanX = Viewer.panX;
                        win.dragPanY = Viewer.panY;
                    }
                    onPositionChanged: m => {
                        // at fit the picture is not draggable (the cursor says so)
                        if (!(m.buttons & Qt.LeftButton) || Viewer.zoom <= 1.05) return;
                        Viewer.panX = win.dragPanX + (m.x - win.dragStartX);
                        Viewer.panY = win.dragPanY + (m.y - win.dragStartY);
                    }
                    onPressAndHold: Hold.hold(held)
                    onClicked: m => {
                        if (Hold.swallowed(held) || m.button === Qt.RightButton) Viewer.rotate();
                    }
                    onDoubleClicked: {
                        if (Viewer.zoomMode === "fit" || Viewer.zoomMode === "200")
                            Viewer.zoomActual();
                        else
                            Viewer.zoomFit();
                    }
                }
                // with the chrome gone, the way out must stay visible and labelled
                Button {
                    visible: win.immersive
                    z: 10
                    anchors { top: parent.top; right: parent.right; margins: Theme.px(12) }
                    text: Tr.t("Exit full screen (Esc)")
                    onClicked: win.immersive = false
                }
            }

            // toolbar: zoom, rotate + flip, slideshow, grid, thumbs, actions
            RowLayout {
                visible: !win.immersive
                Layout.fillWidth: true
                spacing: Theme.px(4)
                IconButton { icon: "zoom-out"; size: Theme.px(28); tip: Tr.t("Zoom out (−)"); onClicked: Viewer.zoomOut() }
                IconButton { icon: "zoom-in"; size: Theme.px(28); tip: Tr.t("Zoom in (+)"); onClicked: Viewer.zoomIn() }
                IconButton { icon: "zoom-fit-best"; size: Theme.px(28); tip: Tr.t("Fit to window (F)"); on: Viewer.zoomMode === "fit"; onClicked: Viewer.zoomFit() }
                IconButton { icon: "document-save"; size: Theme.px(28); tip: Tr.t("100% (1)"); on: Viewer.zoomMode === "100"; onClicked: Viewer.zoomActual() }
                IconButton { icon: "view-fullscreen"; size: Theme.px(28); tip: Tr.t("200% (2)"); on: Viewer.zoomMode === "200"; onClicked: Viewer.zoom200() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Math.round(Viewer.zoom * 100) + "%" + (Viewer.rotation !== 0 ? "  ·  " + Viewer.rotation + "°" : "")
                        + (Viewer.flipH ? "  ·  " + Tr.t("mirrored") : "")
                        + (Viewer.exifRotation !== 0 ? "  ·  " + Tr.t("EXIF") : "")
                        + (Viewer.slideshow ? "  ·  " + Tr.t("slideshow") : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                IconButton { icon: "object-rotate-right"; size: Theme.px(28); tip: Tr.t("Rotate right (R)"); onClicked: Viewer.rotate() }
                IconButton { icon: "object-rotate-left"; size: Theme.px(28); tip: Tr.t("Rotate left"); onClicked: Viewer.rotateCCW() }
                IconButton { icon: "edit-copy"; size: Theme.px(28); tip: Tr.t("Flip horizontally (H)"); on: Viewer.flipH; onClicked: Viewer.toggleFlipH() }
                IconButton { icon: "edit-copy"; size: Theme.px(28); tip: Tr.t("Flip vertically (V)"); on: Viewer.flipV; onClicked: Viewer.toggleFlipV() }
                IconButton { icon: "media-playback-start"; size: Theme.px(28); tip: Tr.t("Slideshow (S)"); on: Viewer.slideshow; onClicked: Viewer.toggleSlideshow() }
                IconButton { icon: "view-grid"; size: Theme.px(28); tip: Tr.t("Grid (G)"); on: Viewer.gridMode; onClicked: Viewer.toggleGrid() }
                IconButton { icon: "view-list"; size: Theme.px(28); tip: Tr.t("Thumbnails (T)"); on: Viewer.showThumbs; onClicked: Viewer.toggleThumbs() }
                IconButton { icon: "preferences-desktop-wallpaper"; size: Theme.px(28); tip: Tr.t("Set as wallpaper"); onClicked: Viewer.setWallpaper() }
                IconButton { icon: "document-save-as"; size: Theme.px(28); tip: Tr.t("Save as…"); onClicked: win.saveAs() }
                IconButton { icon: "view-fullscreen"; size: Theme.px(28); tip: Tr.t("Full screen (F11)"); on: win.immersive; onClicked: win.immersive = !win.immersive }
                IconButton { icon: "document-edit"; size: Theme.px(28); tip: Tr.t("Crop, draw and save (E)"); on: Viewer.editing; onClicked: Viewer.editing ? Viewer.cancelEdit() : Viewer.startEdit() }
            }
            // editing: the crop's shape, and how it is kept - a copy, or in place
            // (the original goes to the trash, where it can be put back)
            RowLayout {
                Layout.fillWidth: true
                visible: !win.immersive && Viewer.editing
                spacing: Theme.px(6)
                Repeater {
                    model: Viewer.drawing ? [] : [["free", Tr.t("Free")], ["original", Tr.t("Original")], ["square", Tr.t("Square")], ["4:3", "4:3"], ["16:9", "16:9"]]
                    Choice { required property var modelData; text: modelData[1]; selected: Viewer.cropAspect === modelData[0]; onClicked: Viewer.setAspect(modelData[0], cropArea.shownRatio) }
                }
                // markup: a pen in a few colours and sizes; Undo takes the last stroke
                Choice { text: Tr.t("Draw"); selected: Viewer.drawing; onClicked: Viewer.drawing = !Viewer.drawing }
                Repeater {
                    model: Viewer.drawing ? [["pen", Tr.t("Pen")], ["highlight", Tr.t("Highlighter")], ["line", Tr.t("Line")], ["arrow", Tr.t("Arrow")],
                                             ["box", Tr.t("Box")], ["text", Tr.t("Text")], ["blur", Tr.t("Blur")]] : []
                    Choice { required property var modelData; text: modelData[1]; selected: Viewer.tool === modelData[0]; onClicked: Viewer.tool = modelData[0] }
                }
                Repeater {
                    model: Viewer.drawing ? [["#e01b24", Tr.t("Red")], ["#f6d32d", Tr.t("Yellow")], ["#33d17a", Tr.t("Green")], ["#3584e4", Tr.t("Blue")], ["#ffffff", Tr.t("White")], ["#000000", Tr.t("Black")]] : []
                    Rectangle {
                        required property var modelData
                        width: Theme.px(22); height: width; radius: width / 2
                        color: modelData[0]
                        border.width: Viewer.penColor === modelData[0] ? 3 : 1
                        border.color: Viewer.penColor === modelData[0] ? Theme.accent : Theme.border
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData[1]
                        Accessible.checked: Viewer.penColor === modelData[0]
                        Accessible.onPressAction: Viewer.penColor = modelData[0]
                        Accessible.onToggleAction: Viewer.penColor = modelData[0]
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Viewer.penColor = parent.modelData[0] }
                        KeyFocus { onActivated: Viewer.penColor = parent.modelData[0] }
                    }
                }
                Repeater {
                    model: Viewer.drawing ? [[0.004, Tr.t("Thin")], [0.008, Tr.t("Medium")], [0.02, Tr.t("Thick")]] : []
                    Choice { required property var modelData; text: modelData[1]; selected: Math.abs(Viewer.penSize - modelData[0]) < 0.0001; onClicked: Viewer.penSize = modelData[0] }
                }
                // the size it is saved at (Loupe has no resize; Drawing and GIMP do)
                Repeater {
                    model: Viewer.drawing ? [] : [["", Tr.t("Full size")], ["50%", "50%"], ["1920x1920>", Tr.t("Max 1920")], ["1080x1080>", Tr.t("Max 1080")]]
                    Choice { required property var modelData; text: modelData[1]; selected: Viewer.resizeTo === modelData[0]; onClicked: Viewer.resizeTo = modelData[0] }
                }
                IconButton { visible: Viewer.drawing; enabled: Viewer.strokes.length > 0; icon: "edit-undo"; size: Theme.px(26); tip: Tr.t("Undo the last stroke"); onClicked: Viewer.undoStroke() }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: Viewer.cancelEdit() }
                Button { text: Tr.t("Replace"); flat: true; enabled: Viewer.edited && !Viewer.saving; onClicked: Viewer.saveEdit("replace") }
                Button { text: Viewer.saving ? Tr.t("Saving…") : Tr.t("Save a copy"); enabled: Viewer.edited && !Viewer.saving; onClicked: Viewer.saveEdit("copy") }
            }
            RowLayout {
                visible: !win.immersive
                Layout.fillWidth: true
                spacing: Theme.px(4)
                IconButton { icon: "edit-copy"; size: Theme.px(28); tip: Tr.t("Copy path (C)"); onClicked: Viewer.copyPath() }
                IconButton { icon: "folder-open"; size: Theme.px(28); tip: Tr.t("Show in Files"); enabled: Viewer.file !== ""; onClicked: win.reveal(Viewer.file) }
                IconButton { icon: "document-open"; size: Theme.px(28); tip: Tr.t("Open with… (O)"); onClicked: Viewer.openWith() }
                IconButton { icon: "edit-delete"; size: Theme.px(28); tip: win.trashConfirm ? Tr.t("Tap again to trash") : Tr.t("Move to trash (Del)"); onClicked: win.askTrash() }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("← → to browse · wheel to zoom · R to turn · Esc closes")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                    elide: Text.ElideRight
                }
            }

            // thumbnail strip
            Flickable {
                visible: !win.immersive && Viewer.showThumbs && !Viewer.gridMode && Viewer.list.length > 1
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(68)
                clip: true
                contentWidth: thumbRow.width
                contentHeight: thumbRow.height
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: thumbRow
                    spacing: Theme.px(6)
                    Repeater {
                        model: Viewer.list
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: Theme.px(88)
                            height: Theme.px(60)
                            radius: Theme.radiusSmall
                            color: index === Viewer.index ? Theme.alpha(Theme.accent, 0.22) : Theme.surface1
                            border.width: index === Viewer.index ? 2 : 0
                            border.color: Theme.accent
                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.px(4)
                                source: "file://" + modelData
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                cache: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Viewer.goToIndex(index)
                            }
                            KeyFocus { name: String(modelData).split("/").pop(); onActivated: Viewer.goToIndex(index) }
                        }
                    }
                }
            }
        }
    }
}
