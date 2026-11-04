// The screen saver's cover on every screen (Services/ScreenSaver says when):
//   clock  - the wallpaper, dimmed and slowly drifting closer (only on mains
//            power), with a large clock that moves a little every minute so
//            nothing is burnt into an OLED screen
//   photos - the Pictures folder, one picture after another, cross-faded
// It fades in. Real idle ends at the first input by itself; the preview at a
// key or a click.
import Quickshell
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel
import qs.Common
import qs.Services

Variants {
    model: Quickshell.screens
    PanelWindow {
        id: cover
        required property var modelData
        screen: modelData
        visible: ScreenSaver.active
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.namespace: "shani-screensaver"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: ScreenSaver.preview ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        readonly property bool photos: Settings.data.screenSaverStyle === "photos" && pics.count > 0

        Item {
            id: stage
            anchors.fill: parent
            opacity: 0
            // in, slowly - never a jump to black
            NumberAnimation on opacity { id: fadeIn; running: false; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
            Connections { target: cover; function onVisibleChanged() { if (cover.visible) { stage.opacity = 0; fadeIn.restart(); cover.drift(); } } }
            Component.onCompleted: if (cover.visible) { stage.opacity = 0; fadeIn.restart(); cover.drift(); }   // made on first use, already visible

            // ---- clock: the wallpaper, drifting closer
            Image {
                id: wall
                visible: !cover.photos
                anchors.fill: parent
                source: Theme.wallpaper ? "file://" + Theme.wallpaper : ""
                sourceSize: Qt.size(parent.width, parent.height)
                fillMode: Image.PreserveAspectCrop
                opacity: 0.45
                SequentialAnimation on scale {
                    running: cover.visible && !cover.photos && !PowerState.onBattery && !Settings.data.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 1.08; duration: 90000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.08; to: 1; duration: 90000; easing.type: Easing.InOutSine }
                }
            }

            // ---- photos: the Pictures folder, cross-faded every 12 s
            FolderListModel {
                id: pics
                folder: "file://" + (Quickshell.env("XDG_PICTURES_DIR") || Quickshell.env("HOME") + "/Pictures")
                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                showDirs: false
            }
            property int shownA: 0
            property bool onA: true
            function nextPhoto() {
                const i = Math.floor(Math.random() * pics.count);
                if (onA) b.source = pics.get(i, "fileUrl"); else a.source = pics.get(i, "fileUrl");
                onA = !onA;
            }
            Timer { interval: 12000; repeat: true; running: cover.visible && cover.photos; triggeredOnStart: true; onTriggered: stage.nextPhoto() }
            Image { id: a; visible: cover.photos; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(parent.width, parent.height); opacity: stage.onA ? 0 : 1; Behavior on opacity { NumberAnimation { duration: 2000 } } }
            Image { id: b; visible: cover.photos; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(parent.width, parent.height); opacity: stage.onA ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 2000 } } }
            Rectangle { visible: cover.photos; anchors.fill: parent; gradient: Gradient { GradientStop { position: 0.6; color: "transparent" } GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) } } }

            // ---- the clock: large, or small in a corner over photos; it moves
            Column {
                id: face
                spacing: 6
                x: (cover.width - width) / 2 + cover.dx
                y: cover.photos ? cover.height - height - 48 : (cover.height - height) / 2 + cover.dy
                Behavior on x { NumberAnimation { duration: 2500; easing.type: Easing.InOutSine } }
                Behavior on y { NumberAnimation { duration: 2500; easing.type: Easing.InOutSine } }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.date, Settings.data.use24h ? "HH:mm" : "h:mm")
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: (cover.photos ? 64 : 148) * Theme.fontScale
                    font.weight: Font.Light
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(clock.date, "dddd, d MMMM")
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.family: Theme.font
                    font.pixelSize: 22 * Theme.fontScale
                }
            }
        }
        // a step somewhere else each minute (burn-in), at most a sixth of the screen
        property real dx: 0
        property real dy: 0
        function drift() {
            if (Settings.data.reduceMotion) { dx = 0; dy = 0; return; }
            dx = (Math.random() - 0.5) * width / 3;
            dy = (Math.random() - 0.5) * height / 3;
        }
        SystemClock { id: clock; enabled: cover.visible; precision: SystemClock.Minutes; onDateChanged: cover.drift() }
        MouseArea { anchors.fill: parent; onClicked: ScreenSaver.preview = false }
        Item {
            focus: true
            Keys.onPressed: ScreenSaver.preview = false
        }
    }
}
