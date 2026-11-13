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
    implicitWidth: 960
    implicitHeight: 760
    // blur behind the card, as on every shell surface (ext-background-effect)

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: PdfViewer.close()
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
        }
    }
    Item {
        id: blurCard
        anchors.fill: parent
        MouseArea { anchors.fill: parent }       // clicks inside do not close it
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconButton { icon: "go-previous"; size: 28; tip: Tr.t("Previous page"); onClicked: PdfViewer.prevPage() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: PdfViewer.name + (PdfViewer.label !== "" ? "  ·  " + PdfViewer.label : "")
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-next"; size: 28; tip: Tr.t("Next page"); onClicked: PdfViewer.nextPage() }
                IconButton { icon: "document-open"; size: 28; tip: Tr.t("Toggle thumbnails"); on: PdfViewer.showSidebar; onClicked: PdfViewer.toggleSidebar() }
                IconButton { icon: "printer"; size: 28; tip: Tr.t("Print (P)"); onClicked: PdfViewer.printFile() }
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
                spacing: 6
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Find in document…")
                    label: Tr.t("Find in document")
                    onAccepted: PdfViewer.search(searchField.text)
                }
                IconButton { icon: "go-up"; size: 28; tip: Tr.t("Find previous"); onClicked: PdfViewer.findPrev() }
                IconButton { icon: "go-down"; size: 28; tip: Tr.t("Find next"); onClicked: PdfViewer.findNext() }
                Text {
                    text: PdfViewer.searchLabel !== "" ? PdfViewer.searchLabel : (PdfViewer.searchState !== "" ? PdfViewer.searchState : PdfViewer.label)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                TextField {
                    id: jumpField
                    Layout.preferredWidth: 80
                    placeholder: Tr.t("Page…")
                    label: Tr.t("Go to page")
                    onAccepted: PdfViewer.jumpTo(jumpField.text)
                }
                IconButton { icon: "go-next"; size: 28; tip: Tr.t("Go to page"); onClicked: PdfViewer.jumpTo(jumpField.text) }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // page thumbnails sidebar (+ outline/bookmarks underneath)
                Rectangle {
                    visible: PdfViewer.showSidebar
                    Layout.preferredWidth: 132
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    clip: true
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            contentWidth: thumbCol.width
                            contentHeight: thumbCol.height
                            Column {
                                id: thumbCol
                                spacing: 4
                                Repeater {
                                    model: PdfViewer.pages
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        width: 116
                                        height: 150
                                        radius: Theme.radiusSmall
                                        color: index === PdfViewer.page ? Theme.alpha(Theme.accent, 0.22) : Theme.surface1
                                        border.width: index === PdfViewer.page ? 2 : 0
                                        border.color: Theme.accent
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 5
                                            source: "file://" + modelData
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            cache: true
                                        }
                                        Text {
                                            anchors.bottom: parent.bottom
                                            anchors.right: parent.right
                                            anchors.margins: 4
                                            text: String(index + 1)
                                            color: Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: 10 * Theme.fontScale
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: PdfViewer.goTo(index)
                                        }
                                    }
                                }
                            }
                        }
                        // outline / bookmarks (PyMuPDF)
                        Rectangle {
                            visible: PdfViewer.outline.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
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
                                            width: 110
                                            text: "  ".repeat(modelData.level) + modelData.title
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 10 * Theme.fontScale
                                            elide: Text.ElideRight
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: PdfViewer.goToOutline(index)
                                            }
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
                        Image {
                            id: pageImage
                            visible: PdfViewer.current !== ""
                            anchors.fill: parent
                            anchors.margins: PdfViewer.fitMode === "width" ? 2 : 10
                            source: PdfViewer.current !== "" ? "file://" + PdfViewer.current : ""
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
                        Text {
                            visible: PdfViewer.loading
                            anchors.centerIn: parent
                            text: Tr.t("Rendering pages…")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 13 * Theme.fontScale
                        }
                        Text {
                            visible: !PdfViewer.loading && PdfViewer.current === ""
                            anchors.centerIn: parent
                            text: PdfViewer.error !== "" ? PdfViewer.error : Tr.t("No pages yet")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 13 * Theme.fontScale
                        }
                        MouseArea {
                            anchors.fill: parent
                            onWheel: w => { if (w.angleDelta.y < 0) PdfViewer.nextPage(); else PdfViewer.prevPage(); }
                            onClicked: m => { if (m.x > width / 2) PdfViewer.nextPage(); else PdfViewer.prevPage(); }
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
                            spacing: 8
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Repeater {
                                model: PdfViewer.pages
                                Image {
                                    required property var modelData
                                    required property int index
                                    width: 640
                                    height: 800
                                    x: 8
                                    source: "file://" + modelData
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    cache: false
                                    rotation: PdfViewer.rotation
                                }
                            }
                        }
                    }
                }

                // the form's fields, one control each; the copy is saved beside the PDF
                Rectangle {
                    visible: PdfViewer.formShown
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 10
                        contentHeight: formCol.implicitHeight
                        clip: true
                        ColumnLayout {
                            id: formCol
                            width: parent.width
                            spacing: 8
                            SectionTitle { Layout.fillWidth: true; text: Tr.t("Fill in") }
                            Repeater {
                                model: PdfViewer.formFields
                                ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        visible: modelData.type !== "checkbox"
                                        text: modelData.label.replace(/_/g, " ")
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: 11 * Theme.fontScale
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
                                        spacing: 6
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
                                font.pixelSize: 11 * Theme.fontScale
                            }
                            Button { visible: PdfViewer.formSaved !== ""; flat: true; text: Tr.t("Open the filled copy"); onClicked: PdfViewer.open(PdfViewer.formSaved) }
                        }
                    }
                }
            }

            // fit / continuous / rotation toolbar
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                IconButton { icon: "zoom-fit-best"; size: 28; tip: Tr.t("Fit page (F)"); on: PdfViewer.fitMode === "page"; onClicked: PdfViewer.setFit("page") }
                IconButton { icon: "view-fullscreen"; size: 28; tip: Tr.t("Fit width (W)"); on: PdfViewer.fitMode === "width"; onClicked: PdfViewer.setFit("width") }
                IconButton { icon: "document-save"; size: 28; tip: Tr.t("Actual size"); on: PdfViewer.fitMode === "actual"; onClicked: PdfViewer.setFit("actual") }
                IconButton { icon: "view-dual"; size: 28; tip: Tr.t("Continuous scroll"); on: PdfViewer.continuous; onClicked: PdfViewer.toggleContinuous() }
                IconButton { icon: "object-rotate-right"; size: 28; tip: Tr.t("Rotate right (R)"); onClicked: PdfViewer.rotate() }
                IconButton { icon: "object-rotate-left"; size: 28; tip: Tr.t("Rotate left"); onClicked: PdfViewer.rotateCCW() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: (PdfViewer.label !== "" ? PdfViewer.label + "  ·  " : "") + Tr.t("← → to turn pages · Esc closes")
                        + (PdfViewer.rotation !== 0 ? "  ·  " + PdfViewer.rotation + "°" : "")
                        + (PdfViewer.fitMode === "width" ? "  ·  " + Tr.t("fit width") : PdfViewer.fitMode === "actual" ? "  ·  " + Tr.t("actual size") : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                    elide: Text.ElideRight
                }
            }
        }
    }
}
