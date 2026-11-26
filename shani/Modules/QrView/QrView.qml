// A QR code to point a phone at (Qr): the Wi-Fi, a link, a bit of text.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    visible: Qr.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-qr"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { objectName: "nav:pointer"; anchors.fill: parent; onClicked: Qr.close() }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Qr.close() }
    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Theme.px(360)
        implicitHeight: col.implicitHeight + 40
        strong: true
        radius: Theme.radiusLarge
        ColumnLayout {
            id: col
            x: 20
            y: 20
            width: parent.width - 40
            spacing: Theme.px(12)
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qr.title
                color: Theme.text
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.type("heading")
                font.weight: Font.DemiBold
            }
            // white around the code, whatever the style: scanners want the quiet zone light
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Theme.px(280)
                implicitHeight: Theme.px(280)
                radius: Theme.px(12)
                color: "white"
                Image {
                    id: qrImage
                    anchors.fill: parent
                    anchors.margins: Theme.px(10)
                    source: Qr.image ? "file://" + Qr.image + "?" + Qr.rev : ""
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "QR code: " + Qr.title
                }
                Text {
                    anchors.centerIn: parent
                    visible: qrImage.status === Image.Error
                    text: Tr.t("QR code unavailable")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Point a phone's camera at it · Esc closes")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
            }
            // if scanning fails, the encoded details are still readable here
            Text {
                Layout.fillWidth: true
                visible: Qr.text !== ""
                text: Qr.text
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.mono
                font.pixelSize: Theme.type("small")
            }
            Button {
                Layout.alignment: Qt.AlignHCenter
                visible: Qr.text !== ""
                enabled: Qr.text !== ""
                text: Tr.t("Copy details")
                onClicked: Quickshell.clipboardText = Qr.text
            }
            Button {
                Layout.alignment: Qt.AlignHCenter
                visible: Qr.shown
                enabled: Qr.image !== ""
                text: Tr.t("Save PNG…")
                onClicked: FilePicker.open({
                    mode: "save",
                    title: Tr.t("Save QR code"),
                    defaultName: "shani-qr.png",
                    filters: ["png"],
                    onPicked: paths => { if (paths.length) Qr.saveTo(paths[0]); }
                })
            }
        }
    }
}
