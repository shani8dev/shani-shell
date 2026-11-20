// A PDF, page by page (PdfReader) — Papers/Evince parity: page thumbnails
// sidebar, text search (pdftotext -bbox, word highlighted over the page,
// with a jump-to-page box as well), outline/bookmarks, fit-width/fit-page,
// continuous scroll option, rotation, print button (lp via Printing).
// poppler's PNGs in ~/.cache/shani-pdf, ← → or wheel to turn, Esc closes.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Document Viewer"
    visible: PdfViewer.shown
    onGone: PdfViewer.close()
    margins: 0
    implicitWidth: Theme.px(960)
    implicitHeight: Theme.px(760)
    // blur behind the card, as on every shell surface (ext-background-effect)

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

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: PdfViewer.info !== null ? PdfViewer.info = null : PdfViewer.close()
        Keys.onRightPressed: PdfViewer.nextPage()
        Keys.onLeftPressed: PdfViewer.prevPage()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_PageDown) PdfViewer.nextPage();
            else if (e.key === Qt.Key_PageUp) PdfViewer.prevPage();
            else if (e.key === Qt.Key_R && (e.modifiers & Qt.ShiftModifier)) PdfViewer.rotateCCW();
            else if (e.key === Qt.Key_R) PdfViewer.rotate();
            else if (e.key === Qt.Key_F) PdfViewer.setFit("page");
            else if (e.key === Qt.Key_W) PdfViewer.setFit("width");
            else if (e.key === Qt.Key_P) PdfViewer.printFile();
            else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) PdfViewer.setZoom(PdfViewer.zoom * 1.25);
            else if (e.key === Qt.Key_Minus) PdfViewer.setZoom(PdfViewer.zoom / 1.25);
            else if (e.key === Qt.Key_0) PdfViewer.setZoom(1);
        }
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
                IconButton { icon: "go-previous"; size: Theme.px(28); tip: Tr.t("Previous page"); onClicked: PdfViewer.prevPage() }
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
                IconButton { icon: "go-next"; size: Theme.px(28); tip: Tr.t("Next page"); onClicked: PdfViewer.nextPage() }
                IconButton { icon: "document-open"; size: Theme.px(28); tip: Tr.t("Toggle thumbnails"); on: PdfViewer.showSidebar; onClicked: PdfViewer.toggleSidebar() }
                IconButton { icon: "printer"; size: Theme.px(28); tip: Tr.t("Print (P)"); onClicked: PdfViewer.printFile() }
                IconButton { icon: "weather-clear-night"; size: Theme.px(28); tip: Tr.t("Night mode"); on: PdfViewer.night; onClicked: PdfViewer.setNight(!PdfViewer.night) }
                IconButton { icon: "format-text-direction-ltr"; size: Theme.px(28); tip: Tr.t("Read as text (select and copy)"); on: PdfViewer.textMode; onClicked: PdfViewer.textMode = !PdfViewer.textMode }
                IconButton { icon: "edit-copy"; size: Theme.px(28); tip: Tr.t("Copy this page's text"); onClicked: PdfViewer.copyPageText() }
                IconButton { icon: "document-properties"; size: Theme.px(28); tip: Tr.t("Document properties"); onClicked: PdfViewer.showInfo() }
                // a form: fill it in, save a filled copy
                Button {
                    visible: PdfViewer.formFields.length > 0
                    text: Tr.t("Fill in (%1)", PdfViewer.formFields.length)
                    kind: PdfViewer.formShown ? "primary" : ""
                    onClicked: PdfViewer.formShown = !PdfViewer.formShown
                }
            }

            // search bar: find text (pdftotext -bbox) + jump-to-page box
            RowLayout {
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
                        Image {
                            id: pageImage
                            visible: PdfViewer.current !== ""
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
                            visible: !PdfViewer.continuous && PdfViewer.highlight !== null && PdfViewer.highlight.page === PdfViewer.page
                                && PdfViewer.highlight.x1 > PdfViewer.highlight.x0
                            x: PdfViewer.highlight ? (PdfViewer.highlight.x0 / PdfViewer.highlight.pageW) * parent.width : 0
                            y: PdfViewer.highlight ? (PdfViewer.highlight.y0 / PdfViewer.highlight.pageH) * parent.height : 0
                            width: PdfViewer.highlight ? ((PdfViewer.highlight.x1 - PdfViewer.highlight.x0) / PdfViewer.highlight.pageW) * parent.width : 0
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
                                else if (w.angleDelta.y < 0) PdfViewer.nextPage(); else PdfViewer.prevPage();
                            }
                            onClicked: m => { if (PdfViewer.zoom > 1.01) return; if (m.x > width / 2) PdfViewer.nextPage(); else PdfViewer.prevPage(); }
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
                        Text {
                            visible: PdfViewer.loading
                            anchors.centerIn: parent
                            text: Tr.t("Rendering pages…")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
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
                        Text {
                            visible: !PdfViewer.loading && PdfViewer.current === "" && !PdfViewer.needsPassword
                            anchors.centerIn: parent
                            text: PdfViewer.error !== "" ? PdfViewer.error : Tr.t("No pages yet")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                        }
                    }

                    // continuous scroll: every rendered page, one under the other
                    Flickable {
                        visible: PdfViewer.continuous
                        anchors.fill: parent
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: contCol.width
                        contentHeight: contCol.height
                        Column {
                            id: contCol
                            spacing: Theme.px(8)
                            anchors.leftMargin: Theme.px(8)
                            anchors.rightMargin: Theme.px(8)
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
            }

            // fit / continuous / rotation toolbar
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                IconButton { icon: "zoom-fit-best"; size: Theme.px(28); tip: Tr.t("Fit page (F)"); on: PdfViewer.fitMode === "page"; onClicked: PdfViewer.setFit("page") }
                IconButton { icon: "view-fullscreen"; size: Theme.px(28); tip: Tr.t("Fit width (W)"); on: PdfViewer.fitMode === "width"; onClicked: PdfViewer.setFit("width") }
                IconButton { icon: "document-save"; size: Theme.px(28); tip: Tr.t("Actual size"); on: PdfViewer.fitMode === "actual"; onClicked: PdfViewer.setFit("actual") }
                IconButton { icon: "view-dual"; size: Theme.px(28); tip: Tr.t("Continuous scroll"); on: PdfViewer.continuous; onClicked: PdfViewer.toggleContinuous() }
                IconButton { icon: "object-rotate-right"; size: Theme.px(28); tip: Tr.t("Rotate right (R)"); onClicked: PdfViewer.rotate() }
                IconButton { icon: "object-rotate-left"; size: Theme.px(28); tip: Tr.t("Rotate left"); onClicked: PdfViewer.rotateCCW() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: (PdfViewer.label !== "" ? PdfViewer.label + "  ·  " : "") + Tr.t("← → to turn pages · Esc closes")
                        + (PdfViewer.rotation !== 0 ? "  ·  " + PdfViewer.rotation + "°" : "")
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
