// A PDF, page by page (PdfReader): poppler's PNGs in ~/.cache/shani-pdf,
// wheel or ← → to turn the page, Esc or click to close.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: PdfViewer.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-pdf"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: PdfViewer.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: PdfViewer.close()
        Keys.onRightPressed: PdfViewer.nextPage()
        Keys.onLeftPressed: PdfViewer.prevPage()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_PageDown) PdfViewer.nextPage();
            else if (e.key === Qt.Key_PageUp) PdfViewer.prevPage();
        }
    }
    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(680, parent.width - 80)
        height: Math.min(760, parent.height - 120)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }       // clicks inside do not close it
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: PdfViewer.name + (PdfViewer.label !== "" ? "  ·  " + PdfViewer.label : "")
                color: Theme.text
                elide: Text.ElideMiddle
                font.family: Theme.font
                font.pixelSize: 15 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true
                Image {
                    visible: PdfViewer.current !== ""
                    anchors.fill: parent
                    anchors.margins: 10
                    source: PdfViewer.current !== "" ? "file://" + PdfViewer.current : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    cache: false
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "PDF page " + PdfViewer.label + ": " + PdfViewer.name
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
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: PdfViewer.label !== "" ? PdfViewer.label + "  ·  " + Tr.t("← → to turn pages · Esc closes") : Tr.t("← → to turn pages · Esc closes")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }
}
