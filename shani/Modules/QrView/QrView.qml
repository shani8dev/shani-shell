// A QR code to point a phone at (Qr): the Wi-Fi, a link, a bit of text.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Qr.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-qr"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: Qr.close() }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Qr.close() }
    Glass {
        anchors.centerIn: parent
        width: 360
        implicitHeight: col.implicitHeight + 40
        strong: true
        radius: Theme.radiusLarge
        ColumnLayout {
            id: col
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 12
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qr.title
                color: Theme.text
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 16 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            // white around the code, whatever the style: scanners want the quiet zone light
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 280
                implicitHeight: 280
                radius: 12
                color: "white"
                Image {
                    anchors.fill: parent
                    anchors.margins: 10
                    source: Qr.image ? "file://" + Qr.image + "?" + Qr.rev : ""
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "QR code: " + Qr.title
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Point a phone's camera at it · Esc closes")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }
}
