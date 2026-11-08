// A picture, full size in the shell (Viewer): wheel to zoom, R to turn,
// ← → through its folder, Esc or click to close.
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

    MouseArea { anchors.fill: parent; onClicked: Viewer.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Viewer.close()
        Keys.onRightPressed: Viewer.next()
        Keys.onLeftPressed: Viewer.prev()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_R) Viewer.rotate();
            else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) Viewer.zoomIn();
            else if (e.key === Qt.Key_Minus) Viewer.zoomOut();
            else if (e.key === Qt.Key_0) Viewer.zoomReset();
        }
    }
    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(720, parent.width - 80)
        height: Math.min(560, parent.height - 120)
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
                text: Viewer.name + (Viewer.position !== "" ? "  ·  " + Viewer.position : "")
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
                    anchors.fill: parent
                    anchors.margins: 10
                    source: Viewer.file !== "" ? "file://" + Viewer.file : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    cache: false
                    scale: Viewer.zoom
                    rotation: Viewer.rotation
                    transformOrigin: Item.Center
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "Picture: " + Viewer.name
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onWheel: w => { if (w.angleDelta.y > 0) Viewer.zoomIn(); else Viewer.zoomOut(); }
                    onClicked: m => { if (m.button === Qt.RightButton) Viewer.rotate(); }
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Math.round(Viewer.zoom * 100) + "%" + (Viewer.rotation !== 0 ? "  ·  " + Viewer.rotation + "°" : "") + "  ·  " + Tr.t("← → to browse · wheel to zoom · R to turn · Esc closes")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }
}
