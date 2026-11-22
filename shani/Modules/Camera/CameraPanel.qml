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
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Camera"
    visible: Camera.open
    onGone: Camera.closeCamera()
    margins: 0
    implicitWidth: Theme.px(720)
    implicitHeight: Math.max(320, Math.min(900, col.implicitHeight + 40))

    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Camera.closeCamera() }
    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            spacing: Theme.px(12)

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    // what is happening; the window's header names the app
                    text: Camera.phase === "recording" ? "Recording · " + Camera.elapsed
                        : Camera.phase === "counting" ? "Photo in " + Camera.countdown + "…"
                        : ""
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(15) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "view-refresh"; size: Theme.px(28); onClicked: Camera.openViewfinder() }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
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
                Choice { text: Tr.t("Photo"); selected: Camera.mode === "photo"; onClicked: Camera.mode = "photo" }
                Choice { text: Tr.t("Video"); selected: Camera.mode === "video"; onClicked: Camera.mode = "video" }
                Choice { text: Tr.t("Mic"); selected: Camera.withAudio; onClicked: Camera.withAudio = !Camera.withAudio }
            }

            // capture settings: self-timer, picture format, video codec
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text { text: Tr.t("Timer"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Repeater {
                    model: [[0, Tr.t("Off")], [3, "3 s"], [5, "5 s"], [10, "10 s"]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: Camera.selfTimer === modelData[0]
                        onClicked: Camera.selfTimer = modelData[0]
                    }
                }
                Item { Layout.fillWidth: true }
                Text { text: Tr.t("Photo"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: "PNG"; selected: Camera.photoFormat === "png"; onClicked: Camera.photoFormat = "png" }
                Choice { text: "JPG"; selected: Camera.photoFormat === "jpg"; onClicked: Camera.photoFormat = "jpg" }
                Text { text: Tr.t("Video"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: "WebM"; selected: Camera.videoFormat === "webm"; onClicked: Camera.videoFormat = "webm" }
                Choice { text: "MP4"; selected: Camera.videoFormat === "mp4"; onClicked: Camera.videoFormat = "mp4" }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Theme.px(120)
                Layout.preferredHeight: Theme.px(56)
                radius: Theme.px(28)
                color: Camera.phase === "recording" ? Theme.red : Theme.accent
                Accessible.role: Accessible.Button
                Accessible.name: shutterText.text
                MouseArea { anchors.fill: parent; onClicked: Camera.shutter() }
                KeyFocus { onActivated: Camera.shutter() }
                Text {
                    id: shutterText
                    anchors.centerIn: parent
                    text: Camera.phase === "recording" ? Tr.t("Stop") : Camera.mode === "video" ? Tr.t("Record") : Tr.t("Photo")
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: Theme.px(16) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(12)
                Rectangle {
                    Layout.preferredWidth: Theme.px(220)
                    Layout.preferredHeight: Theme.px(140)
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    Image {
                        anchors.fill: parent
                        anchors.margins: Theme.px(6)
                        source: /\.(png|jpg)$/i.test(Camera.last) ? "file://" + Camera.last : ""
                        fillMode: Image.PreserveAspectFit
                        visible: /\.(png|jpg)$/i.test(Camera.last)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Camera.available ? "No capture yet" : "No camera found"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        visible: Camera.last === ""
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Text {
                        text: Camera.last ? Camera.last : Camera.available ? "Last capture appears here" : "Connect a camera, or check the camera switch."
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        spacing: Theme.px(6)
                        Choice { text: Tr.t("Open folder"); onClicked: Qt.openUrlExternally("file://" + (Camera.last ? Camera.last.substring(0, Camera.last.lastIndexOf("/")) : Camera.photosDir)); }
                        Choice { text: Tr.t("Copy path"); enabled: Camera.last !== ""; onClicked: Quickshell.clipboardText = Camera.last; }
                        Choice { text: Tr.t("Trim video"); visible: /\.(webm|mp4)$/i.test(Camera.last); onClicked: { const p = Camera.last; Camera.closeCamera(); VideoTrimmer.open(p); } }
                    }
                }
            }

            Text {
                text: Tr.t("Gallery")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(180, count * 44)
                model: Camera.gallery
                spacing: Theme.px(4)
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: Theme.px(44)
                    radius: Theme.radiusSmall
                    color: galArea.containsMouse ? Theme.hover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(10)
                        anchors.rightMargin: Theme.px(6)
                        spacing: Theme.px(6)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text; elide: Text.ElideMiddle; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                            Text { Layout.fillWidth: true; text: modelData.when; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                        }
                        IconButton { icon: "edit-delete"; size: Theme.px(26); tip: Tr.t("Delete capture"); Accessible.name: Tr.t("Delete capture"); onClicked: Camera.trash(modelData.path) }
                    }
                    MouseArea { id: galArea; anchors.fill: parent; z: -1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Viewer.open(modelData.path) }
                }
            }
        }
    }
}
