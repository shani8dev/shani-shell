// Signed (Omarchy Signed parity): sign a PDF or fill a field on it.
// The page is the existing PdfViewer's render; the signature overlay
// sits where Signer.x / Signer.y put it (scaled by Signer.scale), the
// fill text where textX / textY put it. "Save signed copy" composites
// both onto a fresh pdftoppm render with ImageMagick `convert` and
// writes "* - signed.pdf" beside the original (Services/Signer).
// In the QrView PanelWindow pattern.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.signed && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-signed"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // made on first use: the native picker is the portal's, and made with
    // every picker it held the whole shell while D-Bus waited for it
    Loader {
        id: sigFileDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Choose signature")
            nameFilters: [Tr.t("Signature images") + " (*.png *.jpg *.jpeg)", Tr.t("All files") + " (*)"]
            onAccepted: Signer.setSignature(selectedFile.toString().replace(/^file:\/\//, ""))
        }
    }

    MouseArea { anchors.fill: parent; onClicked: Signer.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Signer.close()
        Keys.onRightPressed: PdfViewer.nextPage()
        Keys.onLeftPressed: PdfViewer.prevPage()
    }

    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(920, parent.width - 80)
        height: Math.min(720, parent.height - 100)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "x-office-document"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Signed") + (Signer.name !== "" ? "  ·  " + Signer.name : "")
                        + (PdfViewer.label !== "" ? "  ·  " + PdfViewer.label : "")
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "go-previous"; size: 28; tip: Tr.t("Previous page"); onClicked: PdfViewer.prevPage() }
                IconButton { icon: "go-next"; size: 28; tip: Tr.t("Next page"); onClicked: PdfViewer.nextPage() }
                IconButton { icon: "window-close"; size: 28; tip: Tr.t("Close (Esc)"); onClicked: Signer.close() }
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
                    text: Signer.file
                    onAccepted: Signer.open(text)
                }
                Button { text: Tr.t("Open"); onClicked: Signer.open(pdfField.text) }
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
                        Accessible.name: "PDF page: " + Signer.name
                    }
                    // the signature, where it will land on the saved copy
                    Image {
                        visible: Signer.signature !== "" && PdfViewer.current !== ""
                        x: Signer.x
                        y: Signer.y
                        width: 180 * Signer.scale
                        height: 70 * Signer.scale
                        source: Signer.signature !== "" ? "file://" + Signer.signature : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        cache: false
                    }
                    // the fill text, where it will land
                    Text {
                        visible: Signer.fillText !== ""
                        x: Signer.textX
                        y: Signer.textY
                        text: Signer.fillText
                        color: "black"
                        font.family: Theme.font
                        font.pixelSize: Math.max(8, Signer.textSize * 0.6)
                    }
                    Text {
                        visible: PdfViewer.current === ""
                        anchors.centerIn: parent
                        text: Signer.error !== "" ? Signer.error : Tr.t("Open a PDF to sign")
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
                        text: Signer.signature
                        onAccepted: Signer.setSignature(text)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        TextField {
                            id: xField
                            Layout.fillWidth: true
                            placeholder: "x"
                            label: Tr.t("Signature x position")
                            text: String(Signer.x)
                            onAccepted: Signer.setPosition(text, yField.text)
                        }
                        TextField {
                            id: yField
                            Layout.fillWidth: true
                            placeholder: "y"
                            label: Tr.t("Signature y position")
                            text: String(Signer.y)
                            onAccepted: Signer.setPosition(xField.text, text)
                        }
                        TextField {
                            id: scaleField
                            Layout.fillWidth: true
                            placeholder: "scale"
                            label: Tr.t("Signature scale")
                            text: String(Signer.scale)
                            onAccepted: Signer.setScale(text)
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
                        text: Signer.fillText
                        onAccepted: Signer.setFillText(text)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        TextField {
                            id: textXField
                            Layout.fillWidth: true
                            placeholder: "x"
                            label: Tr.t("Fill text x position")
                            text: String(Signer.textX)
                            onAccepted: Signer.setTextPosition(text, textYField.text)
                        }
                        TextField {
                            id: textYField
                            Layout.fillWidth: true
                            placeholder: "y"
                            label: Tr.t("Fill text y position")
                            text: String(Signer.textY)
                            onAccepted: Signer.setTextPosition(textXField.text, text)
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Button {
                        Layout.fillWidth: true
                        text: Signer.saving ? Tr.t("Saving…") : Tr.t("Save signed copy")
                        kind: "primary"
                        enabled: !Signer.saving && Signer.file !== ""
                        onClicked: Signer.save()
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: Signer.signedFile !== "" || Signer.status !== "" || Signer.error !== ""
                        text: Signer.error !== "" ? Signer.error : (Signer.signedFile !== "" ? Signer.signedFile : Signer.status)
                        color: Signer.error !== "" ? Theme.red : Theme.dim
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Saves “%1 - signed.pdf” beside the original · Esc closes").arg(Signer.name || "doc.pdf")
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
