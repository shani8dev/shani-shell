// A picture, full size in the shell (Viewer) — Loupe parity: zoom to cursor
// (wheel), fit / 100% / 200%, rotate + flip, slideshow, thumbnail strip,
// EXIF-aware rotation (applied by the service), batch grid mode, copy path,
// open-with, delete-to-trash. ← → through its folder, Esc or click to close.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Viewer.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-viewer"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property int dragStartX: 0
    property int dragStartY: 0
    property real dragPanX: 0
    property real dragPanY: 0

    MouseArea { anchors.fill: parent; onClicked: Viewer.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Viewer.close()
        Keys.onRightPressed: Viewer.next()
        Keys.onLeftPressed: Viewer.prev()
        Keys.onHomePressed: if (Viewer.list.length) Viewer.goToIndex(0)
        Keys.onEndPressed: if (Viewer.list.length) Viewer.goToIndex(Viewer.list.length - 1)
        Keys.onPressed: e => {
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
            else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) Viewer.trash();
            else if (e.key === Qt.Key_O) Viewer.openWith();
        }
    }
    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(920, parent.width - 80)
        height: Math.min(720, parent.height - 120)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }       // clicks inside do not close it
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconButton { icon: "go-previous"; size: 28; tip: Tr.t("Previous (←)"); onClicked: Viewer.prev() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Viewer.name + (Viewer.position !== "" ? "  ·  " + Viewer.position : "")
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-next"; size: 28; tip: Tr.t("Next (→)"); onClicked: Viewer.next() }
                IconButton { icon: "window-close"; size: 28; tip: Tr.t("Close (Esc)"); onClicked: Viewer.close() }
            }

            // main stage: single image, or the batch grid
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true

                Image {
                    id: mainImage
                    visible: !Viewer.gridMode
                    width: parent.width
                    height: parent.height
                    x: Viewer.panX
                    y: Viewer.panY
                    source: Viewer.file !== "" ? "file://" + Viewer.file : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    cache: false
                    scale: Viewer.zoom
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
                }
                Text {
                    visible: Viewer.file === ""
                    anchors.centerIn: parent
                    text: Tr.t("No picture")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
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
                        spacing: 8
                        padding: 8
                        Repeater {
                            model: Viewer.list
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: 180
                                height: 140
                                radius: Theme.radiusSmall
                                color: index === Viewer.index ? Theme.alpha(Theme.accent, 0.22) : Theme.surface1
                                border.width: index === Viewer.index ? 2 : 0
                                border.color: Theme.accent
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    source: "file://" + modelData
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    cache: true
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottomMargin: 4
                                    text: String(index + 1)
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 10 * Theme.fontScale
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Viewer.goToIndex(index)
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    visible: !Viewer.gridMode
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Viewer.zoom > 1.05 ? Qt.OpenHandCursor : Qt.ArrowCursor
                    onWheel: w => {
                        const f = w.angleDelta.y > 0 ? 1.2 : 1 / 1.2;
                        Viewer.zoomToCursor(w.x, w.y, f, width, height);
                    }
                    onPressed: m => {
                        win.dragStartX = m.x;
                        win.dragStartY = m.y;
                        win.dragPanX = Viewer.panX;
                        win.dragPanY = Viewer.panY;
                    }
                    onPositionChanged: m => {
                        if (m.buttons & Qt.LeftButton) {
                            Viewer.panX = win.dragPanX + (m.x - win.dragStartX);
                            Viewer.panY = win.dragPanY + (m.y - win.dragStartY);
                        }
                    }
                    onClicked: m => {
                        if (m.button === Qt.RightButton) Viewer.rotate();
                    }
                    onDoubleClicked: {
                        if (Viewer.zoomMode === "fit" || Viewer.zoomMode === "200")
                            Viewer.zoomActual();
                        else
                            Viewer.zoomFit();
                    }
                }
            }

            // toolbar: zoom, rotate + flip, slideshow, grid, thumbs, actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                IconButton { icon: "zoom-out"; size: 28; tip: Tr.t("Zoom out (−)"); onClicked: Viewer.zoomOut() }
                IconButton { icon: "zoom-in"; size: 28; tip: Tr.t("Zoom in (+)"); onClicked: Viewer.zoomIn() }
                IconButton { icon: "zoom-fit-best"; size: 28; tip: Tr.t("Fit to window (F)"); on: Viewer.zoomMode === "fit"; onClicked: Viewer.zoomFit() }
                IconButton { icon: "document-save"; size: 28; tip: Tr.t("100% (1)"); on: Viewer.zoomMode === "100"; onClicked: Viewer.zoomActual() }
                IconButton { icon: "view-fullscreen"; size: 28; tip: Tr.t("200% (2)"); on: Viewer.zoomMode === "200"; onClicked: Viewer.zoom200() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Math.round(Viewer.zoom * 100) + "%" + (Viewer.rotation !== 0 ? "  ·  " + Viewer.rotation + "°" : "")
                        + (Viewer.flipH ? "  ·  " + Tr.t("mirrored") : "")
                        + (Viewer.exifRotation !== 0 ? "  ·  " + Tr.t("EXIF") : "")
                        + (Viewer.slideshow ? "  ·  " + Tr.t("slideshow") : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                }
                IconButton { icon: "object-rotate-right"; size: 28; tip: Tr.t("Rotate right (R)"); onClicked: Viewer.rotate() }
                IconButton { icon: "object-rotate-left"; size: 28; tip: Tr.t("Rotate left"); onClicked: Viewer.rotateCCW() }
                IconButton { icon: "edit-copy"; size: 28; tip: Tr.t("Flip horizontally (H)"); on: Viewer.flipH; onClicked: Viewer.toggleFlipH() }
                IconButton { icon: "edit-copy"; size: 28; tip: Tr.t("Flip vertically (V)"); on: Viewer.flipV; onClicked: Viewer.toggleFlipV() }
                IconButton { icon: "media-playback-start"; size: 28; tip: Tr.t("Slideshow (S)"); on: Viewer.slideshow; onClicked: Viewer.toggleSlideshow() }
                IconButton { icon: "view-grid"; size: 28; tip: Tr.t("Grid (G)"); on: Viewer.gridMode; onClicked: Viewer.toggleGrid() }
                IconButton { icon: "view-list-details"; size: 28; tip: Tr.t("Thumbnails (T)"); on: Viewer.showThumbs; onClicked: Viewer.toggleThumbs() }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                IconButton { icon: "edit-copy"; size: 28; tip: Tr.t("Copy path (C)"); onClicked: Viewer.copyPath() }
                IconButton { icon: "document-open"; size: 28; tip: Tr.t("Open with… (O)"); onClicked: Viewer.openWith() }
                IconButton { icon: "edit-delete"; size: 28; tip: Tr.t("Move to trash (Del)"); onClicked: Viewer.trash() }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("← → to browse · wheel to zoom · R to turn · Esc closes")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                    elide: Text.ElideRight
                }
            }

            // thumbnail strip
            Flickable {
                visible: Viewer.showThumbs && !Viewer.gridMode && Viewer.list.length > 1
                Layout.fillWidth: true
                Layout.preferredHeight: 68
                clip: true
                contentWidth: thumbRow.width
                contentHeight: thumbRow.height
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: thumbRow
                    spacing: 6
                    Repeater {
                        model: Viewer.list
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: 88
                            height: 60
                            radius: Theme.radiusSmall
                            color: index === Viewer.index ? Theme.alpha(Theme.accent, 0.22) : Theme.surface1
                            border.width: index === Viewer.index ? 2 : 0
                            border.color: Theme.accent
                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
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
                        }
                    }
                }
            }
        }
    }
}
