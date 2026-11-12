// PDF Signer: sign a PDF or fill a field on it.
// The page is the existing PdfViewer's render; the signature overlay
// sits where PdfSigner.x / PdfSigner.y put it (scaled by PdfSigner.scale), the
// fill text where textX / textY put it. "Save signed copy" composites
// both onto a fresh pdftoppm render with ImageMagick `convert` and
// writes "* - signed.pdf" beside the original (Services/PdfSigner).
// In the QrView PanelWindow pattern.
import Quickshell
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "PDF Signer"
    visible: Ui.pdfSigner
    onGone: PdfSigner.close()
    margins: 0
    implicitWidth: 920
    implicitHeight: 720

    // made on first use: the native picker is the portal's, and made with
    // every picker it held the whole shell while D-Bus waited for it
    Loader {
        id: sigFileDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Choose signature")
            nameFilters: [Tr.t("Signature images") + " (*.png *.jpg *.jpeg)", Tr.t("All files") + " (*)"]
            onAccepted: PdfSigner.setSignature(selectedFile.toString().replace(/^file:\/\//, ""))
        }
    }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: PdfSigner.close()
        Keys.onRightPressed: PdfViewer.nextPage()
        Keys.onLeftPressed: PdfViewer.prevPage()
    }

    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "x-office-document"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: PdfSigner.name
                        + (PdfViewer.label !== "" ? "  ·  " + PdfViewer.label : "")
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-previous"; size: 28; tip: Tr.t("Previous page"); onClicked: PdfViewer.prevPage() }
                IconButton { icon: "go-next"; size: 28; tip: Tr.t("Next page"); onClicked: PdfViewer.nextPage() }
            }

            // open a PDF: a path, or a folder (its last PDF is opened)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                TextField {
                    id: pdfField
                    Layout.fillWidth: true
                    placeholder: Tr.t("PDF path, or a folder (its last PDF)…")
                    label: Tr.t("PDF path")
                    text: PdfSigner.file
                    onAccepted: PdfSigner.open(text)
                }
                Button { text: Tr.t("Open"); onClicked: PdfSigner.open(pdfField.text) }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // the page, as PdfViewer rendered it, with the overlays
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    clip: true
                    Image {
                        id: pageImage
                        anchors.fill: parent
                        anchors.margins: 10
                        source: PdfViewer.current !== "" ? "file://" + PdfViewer.current : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        cache: false
                        Accessible.role: Accessible.Graphic
                        Accessible.name: "PDF page: " + PdfSigner.name
                    }
                    // the signature, where it will land on the saved copy
                    Image {
                        visible: PdfSigner.signature !== "" && PdfViewer.current !== ""
                        x: PdfSigner.x
                        y: PdfSigner.y
                        width: 180 * PdfSigner.scale
                        height: 70 * PdfSigner.scale
                        source: PdfSigner.signature !== "" ? "file://" + PdfSigner.signature : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        cache: false
                    }
                    // the fill text, where it will land
                    Text {
                        visible: PdfSigner.fillText !== ""
                        x: PdfSigner.textX
                        y: PdfSigner.textY
                        text: PdfSigner.fillText
                        color: "black"
                        font.family: Theme.font
                        font.pixelSize: Math.max(8, PdfSigner.textSize * 0.6)
                    }
                    Text {
                        visible: PdfViewer.current === ""
                        anchors.centerIn: parent
                        text: PdfSigner.error !== "" ? PdfSigner.error : Tr.t("Open a PDF to sign")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 13 * Theme.fontScale
                    }
                    MouseArea {
                        anchors.fill: parent
                        onWheel: w => { if (w.angleDelta.y < 0) PdfViewer.nextPage(); else PdfViewer.prevPage(); }
                    }
                }

                // placement + fill controls, beside the page
                ColumnLayout {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true
                    spacing: 8

                    SectionTitle { Layout.fillWidth: true; text: Tr.t("Signature") }
                    Button {
                        Layout.fillWidth: true
                        text: Tr.t("Choose signature")
                        onClicked: sigFileDlg.open()
                    }
                    TextField {
                        id: sigField
                        Layout.fillWidth: true
                        placeholder: Tr.t("Signature image path")
                        label: Tr.t("Signature image path")
                        text: PdfSigner.signature
                        onAccepted: PdfSigner.setSignature(text)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        TextField {
                            id: xField
                            Layout.fillWidth: true
                            placeholder: "x"
                            label: Tr.t("Signature x position")
                            text: String(PdfSigner.x)
                            onAccepted: PdfSigner.setPosition(text, yField.text)
                        }
                        TextField {
                            id: yField
                            Layout.fillWidth: true
                            placeholder: "y"
                            label: Tr.t("Signature y position")
                            text: String(PdfSigner.y)
                            onAccepted: PdfSigner.setPosition(xField.text, text)
                        }
                        TextField {
                            id: scaleField
                            Layout.fillWidth: true
                            placeholder: "scale"
                            label: Tr.t("Signature scale")
                            text: String(PdfSigner.scale)
                            onAccepted: PdfSigner.setScale(text)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("x / y / scale place the signature on the page")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                    }

                    SectionTitle { Layout.fillWidth: true; text: Tr.t("Fill text") }
                    TextField {
                        id: fillField
                        Layout.fillWidth: true
                        placeholder: Tr.t("Type text to fill…")
                        label: Tr.t("Fill text")
                        text: PdfSigner.fillText
                        onAccepted: PdfSigner.setFillText(text)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        TextField {
                            id: textXField
                            Layout.fillWidth: true
                            placeholder: "x"
                            label: Tr.t("Fill text x position")
                            text: String(PdfSigner.textX)
                            onAccepted: PdfSigner.setTextPosition(text, textYField.text)
                        }
                        TextField {
                            id: textYField
                            Layout.fillWidth: true
                            placeholder: "y"
                            label: Tr.t("Fill text y position")
                            text: String(PdfSigner.textY)
                            onAccepted: PdfSigner.setTextPosition(textXField.text, text)
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Button {
                        Layout.fillWidth: true
                        text: PdfSigner.saving ? Tr.t("Saving…") : Tr.t("Save signed copy")
                        kind: "primary"
                        enabled: !PdfSigner.saving && PdfSigner.file !== ""
                        onClicked: PdfSigner.save()
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: PdfSigner.pdfSignerFile !== "" || PdfSigner.status !== "" || PdfSigner.error !== ""
                        text: PdfSigner.error !== "" ? PdfSigner.error : (PdfSigner.pdfSignerFile !== "" ? PdfSigner.pdfSignerFile : PdfSigner.status)
                        color: PdfSigner.error !== "" ? Theme.red : Theme.dim
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Saves “%1 - signed.pdf” beside the original · Esc closes").arg(PdfSigner.name || "doc.pdf")
                        color: Theme.faint
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                    }
                }
            }
        }
    }
}
