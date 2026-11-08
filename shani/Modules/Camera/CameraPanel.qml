// The camera (Snapshot parity): live preview, photo/video shutter, modes,
// and a gallery of the last captures.
//
// The live preview is libcamera's qcam - the Camera service opens it as a
// window (open()), the panel is the controls around it: camera picker, mode,
// big shutter, countdown/recording, and a gallery of ~/Pictures/Camera and
// ~/Videos/Camera (click a row = image viewer; delete = gio trash). No
// GNOME app involved; cam/qcam are in the image via shani-video.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Camera.open
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-camera"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: Camera.closeCamera() }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Camera.closeCamera() }
    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(720, parent.width - 80)
        implicitHeight: col.implicitHeight + 40
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "camera-photo"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Camera.phase === "recording" ? "Recording · " + Camera.elapsed
                        : Camera.phase === "counting" ? "Photo in " + Camera.countdown + "…"
                        : "Camera"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "view-refresh"; size: 28; onClicked: Camera.openViewfinder() }
                IconButton { icon: "window-close"; size: 28; onClicked: Camera.closeCamera() }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: Camera.cameras
                    Choice {
                        required property var modelData
                        text: modelData.name
                        selected: Camera.selected === modelData.index
                        onClicked: Camera.selected = modelData.index
                    }
                }
                Item { Layout.fillWidth: true }
                Choice { text: "Photo"; selected: Camera.mode === "photo"; onClicked: Camera.mode = "photo" }
                Choice { text: "Video"; selected: Camera.mode === "video"; onClicked: Camera.mode = "video" }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 120
                Layout.preferredHeight: 56
                radius: 28
                color: Camera.phase === "recording" ? Theme.red : Theme.accent
                MouseArea { anchors.fill: parent; onClicked: Camera.shutter() }
                Text {
                    anchors.centerIn: parent
                    text: Camera.phase === "recording" ? "Stop" : Camera.mode === "video" ? "Record" : "Photo"
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: 16 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 140
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    Image {
                        anchors.fill: parent
                        anchors.margins: 6
                        source: Camera.last !== "" && Camera.last.endsWith(".png") ? "file://" + Camera.last : ""
                        fillMode: Image.PreserveAspectFit
                        visible: Camera.last.endsWith(".png")
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Camera.available ? "No capture yet" : "No camera found"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        visible: Camera.last === ""
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: Camera.last ? Camera.last : Camera.available ? "Last capture appears here" : "Connect a camera, or check the camera switch."
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        spacing: 6
                        Choice { text: "Open folder"; onClicked: Qt.openUrlExternally("file://" + (Camera.last ? Camera.last.substring(0, Camera.last.lastIndexOf("/")) : Camera.photosDir)); }
                        Choice { text: "Copy path"; onClicked: Quickshell.clipboardText = Camera.last; }
                    }
                }
            }

            Text {
                text: "Gallery"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(180, gallery.count * 44)
                model: Camera.gallery
                spacing: 4
                delegate: ListRow {
                    title: modelData.name
                    subtitle: modelData.when
                    onClicked: Viewer.open(modelData.path)
                }
            }
        }
    }
}
