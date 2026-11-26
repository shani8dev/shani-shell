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
    // the last capture is a narrow column beside the quick actions on a
    // desktop; on a phone the header's menu button opens it as a drawer
    sidePane: capturePane
    Connections { target: Camera; function onLastChanged() { if (win.compact && Camera.last !== "") capturePane.open = true; } }

    // Camera-like keys: Space shoots, C switches mode, G/F/B/T toggle the
    // overlays, X/Z nudge zoom and exposure. A focused control already takes
    // Space (KeyFocus accepts it), so never steal an event twice.
    function shortcut(e) {
        const k = e.key;
        if (k === Qt.Key_Space) Camera.shutter();
        else if (k === Qt.Key_C) Camera.mode = Camera.mode === "photo" ? "video" : "photo";
        else if (k === Qt.Key_G) Camera.grid = !Camera.grid;
        else if (k === Qt.Key_F) Camera.flash = !Camera.flash;
        else if (k === Qt.Key_B) Camera.burst = !Camera.burst;
        else if (k === Qt.Key_T) { const s = [0, 3, 5, 10]; Camera.selfTimer = s[(s.indexOf(Camera.selfTimer) + 1) % s.length]; }
        else if (k === Qt.Key_X) Camera.zoom = Camera.zoom >= 400 ? 100 : Camera.zoom + 50;
        else if (k === Qt.Key_Z) Camera.exposure = Math.max(-2, Camera.exposure - 0.5);
        else return;
        e.accepted = true;
    }

    Item {
        anchors.fill: parent; focus: win.visible
        Keys.onEscapePressed: Camera.closeCamera()
        Keys.onPressed: e => { if (!e.accepted) win.shortcut(e); }
    }
    Item {
        id: blurCard
        anchors.fill: parent

        // the whole panel scrolls on a phone: the wrapped settings rows and
        // gallery can be taller than the screen
        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: col.implicitHeight + Theme.px(40)
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: col
                x: 20; y: 20
                width: parent.width - 40
                spacing: Theme.px(12)

            RowLayout {
                Layout.fillWidth: true
                Text {
                    id: statusText
                    Layout.fillWidth: true
                    // what is happening; the window's header names the app
                    text: Camera.phase === "recording" ? "Recording · " + Camera.elapsed
                        : Camera.phase === "counting" ? "Photo in " + Camera.countdown + "…"
                        : Camera.phase === "capturing" ? Tr.t("Saving photo…")
                        : ""
                    Accessible.name: text
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(15) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "view-refresh"; tip: Tr.t("Open the camera"); size: Theme.px(28); onClicked: Camera.openViewfinder() }
            }

            // The live view is qcam's own window; this is the surface our
            // overlays and status sit on, so the countdown is seen even there.
            Rectangle {
                id: preview
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(210)
                radius: Theme.radiusSmall
                color: Theme.hover
                clip: true
                Accessible.role: Accessible.Graphic
                Accessible.name: Camera.available ? Tr.t("Camera preview; the live view opens in qcam") : (Camera.error || Tr.t("No camera preview"))

                Text {
                    anchors.centerIn: parent
                    text: Camera.available ? Tr.t("Live preview opens in qcam") : Tr.t("No camera found")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Repeater {
                    model: 2
                    Rectangle { x: preview.width * (index + 1) / 3; y: 0; width: 1; height: preview.height; color: Theme.alpha(Theme.text, 0.35); visible: Camera.grid; Accessible.ignored: true }
                }
                Repeater {
                    model: 2
                    Rectangle { x: 0; y: preview.height * (index + 1) / 3; width: preview.width; height: 1; color: Theme.alpha(Theme.text, 0.35); visible: Camera.grid; Accessible.ignored: true }
                }
                Rectangle {
                    anchors.top: parent.top; anchors.left: parent.left
                    anchors.margins: Theme.px(8)
                    radius: Theme.px(8)
                    color: Camera.mode === "video" ? Theme.red : Theme.accent
                    Accessible.role: Accessible.StaticText
                    Accessible.name: modeLabel.text
                    Text {
                        id: modeLabel
                        text: Camera.mode === "video" ? Tr.t("Video mode") : Tr.t("Photo mode")
                        color: "white"
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: Camera.phase === "counting"
                    text: String(Camera.countdown)
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: Theme.px(72) * Theme.fontScale
                    font.weight: Font.Bold
                    Accessible.name: Tr.t("Photo in %1 seconds", Camera.countdown)
                }
                Rectangle {
                    anchors.top: parent.top; anchors.right: parent.right
                    anchors.margins: Theme.px(8)
                    radius: Theme.px(8)
                    visible: Camera.phase === "recording"
                    color: Theme.red
                    Accessible.name: Tr.t("Recording") + " " + Camera.elapsed
                    Text {
                        anchors.centerIn: parent
                        text: Tr.t("REC") + " " + Camera.elapsed
                        color: "white"
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                }
                Rectangle { id: flashLayer; anchors.fill: parent; color: "white"; opacity: 0; z: 6; Accessible.ignored: true }
                SequentialAnimation {
                    id: flashAnim
                    NumberAnimation { target: flashLayer; property: "opacity"; from: 0.85; to: 0; duration: Theme.mot(220) }
                }
                Connections { target: Camera; function onFlashTickChanged() { if (Camera.flash) flashAnim.restart(); } }
                EmptyState {
                    visible: Camera.privacyOff || Camera.error !== ""
                    anchors.centerIn: parent
                    width: parent.width - Theme.px(40)
                    icon: "camera-off"
                    title: Camera.privacyOff ? Tr.t("Camera is switched off") : Camera.error
                    subtitle: Camera.privacyOff ? Tr.t("Turn on the camera switch and try again.") : Tr.t("Connect a camera or check the privacy switch.")
                    actionText: Tr.t("Try again")
                    onAction: Camera.refresh()
                }
            }

            // a Flow so a phone wraps the chips instead of cutting them off
            Flow {
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
                Choice { text: Tr.t("Photo"); selected: Camera.mode === "photo"; onClicked: Camera.mode = "photo" }
                Choice { text: Tr.t("Video"); selected: Camera.mode === "video"; onClicked: Camera.mode = "video" }
                Choice { text: Tr.t("Mic"); selected: Camera.withAudio; onClicked: Camera.withAudio = !Camera.withAudio }
            }

            // capture settings: self-timer, picture format, video codec
            Flow {
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
                Text { text: Tr.t("Photo"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: "PNG"; selected: Camera.photoFormat === "png"; onClicked: Camera.photoFormat = "png" }
                Choice { text: "JPG"; selected: Camera.photoFormat === "jpg"; onClicked: Camera.photoFormat = "jpg" }
                Text { text: Tr.t("Video"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: "WebM"; selected: Camera.videoFormat === "webm"; onClicked: Camera.videoFormat = "webm" }
                Choice { text: "MP4"; selected: Camera.videoFormat === "mp4"; onClicked: Camera.videoFormat = "mp4" }
            }

            // studio toggles: overlays, a three-shot strip, and the two still
            // adjustments the cam backend can apply (in the PNG step)
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Choice { text: Tr.t("Grid"); selected: Camera.grid; onClicked: Camera.grid = !Camera.grid }
                Choice { text: Tr.t("Flash"); selected: Camera.flash; onClicked: Camera.flash = !Camera.flash }
                Choice { text: Tr.t("Burst"); selected: Camera.burst; onClicked: Camera.burst = !Camera.burst }
                Text { text: Tr.t("Exposure"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: "-"; onClicked: Camera.exposure = Math.max(-2, Camera.exposure - 0.5); Accessible.name: Tr.t("Less exposure") }
                Text { text: Camera.exposure.toFixed(1) + " EV"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; Accessible.name: Tr.t("Exposure %1 EV", Camera.exposure.toFixed(1)) }
                Choice { text: "+"; onClicked: Camera.exposure = Math.min(2, Camera.exposure + 0.5); Accessible.name: Tr.t("More exposure") }
                Text { text: Tr.t("Zoom"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: "-"; onClicked: Camera.zoom = Math.max(100, Camera.zoom - 50); Accessible.name: Tr.t("Zoom out") }
                Text { text: Camera.zoom + "%"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; Accessible.name: Tr.t("Zoom %1 percent", Camera.zoom) }
                Choice { text: "+"; onClicked: Camera.zoom = Math.min(400, Camera.zoom + 50); Accessible.name: Tr.t("Zoom in") }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Theme.px(120)
                Layout.preferredHeight: Theme.px(56)
                radius: Theme.px(28)
                color: Camera.phase === "recording" ? Theme.red : Theme.accent
                // a shutter that cannot shoot must not look pressable: the
                // service guards too, but the person needs to see why
                enabled: Camera.available && Camera.phase === "idle"
                opacity: enabled ? 1 : 0.5
                Accessible.role: Accessible.Button
                Accessible.name: shutterText.text
                MouseArea { anchors.fill: parent; enabled: parent.enabled; onClicked: Camera.shutter() }
                KeyFocus { enabled: parent.enabled; onActivated: Camera.shutter() }
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
                // the thumbnail folds into a drawer on a phone, so the quick
                // actions below keep the whole screen width
                SidePane {
                    id: capturePane
                    compact: win.compact
                    paneWidth: Theme.px(220)
                    label: Tr.t("Details")
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.px(4)
                        IconButton {
                            visible: capturePane.compact
                            icon: "go-previous"
                            size: Theme.px(28)
                            tip: Tr.t("Back")
                            accessibleName: Tr.t("Back")
                            onClicked: capturePane.open = false
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(140)
                            Layout.maximumHeight: Theme.px(140)
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
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Text {
                        Layout.fillWidth: true
                        text: Camera.last ? Camera.last : Camera.available ? Tr.t("Last capture appears here") : Tr.t("Connect a camera, or check the camera switch.")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        wrapMode: Text.WordWrap
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        Choice { text: Tr.t("Open folder"); onClicked: { Qt.openUrlExternally("file://" + (Camera.last ? Camera.last.substring(0, Camera.last.lastIndexOf("/")) : Camera.photosDir)); capturePane.open = false; } }
                        Choice { text: Tr.t("Open"); enabled: Camera.last !== ""; onClicked: { Camera.openCapture(Camera.last); capturePane.open = false; } }
                        Choice { text: Tr.t("Share"); enabled: Camera.last !== ""; onClicked: { Share.open(Camera.last); capturePane.open = false; } }
                        Choice { text: Tr.t("Copy path"); enabled: Camera.last !== ""; onClicked: { Camera.copyPath(Camera.last); capturePane.open = false; } }
                        Choice { text: Tr.t("Reveal"); enabled: Camera.last !== ""; onClicked: { Camera.reveal(Camera.last); capturePane.open = false; } }
                        Choice { text: Tr.t("Trim video"); visible: /\.(webm|mp4)$/i.test(Camera.last); onClicked: { const p = Camera.last; capturePane.open = false; Camera.closeCamera(); VideoTrimmer.open(p); } }
                    }
                }
            }

            Text {
                text: Tr.t("Gallery")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice { text: Tr.t("All"); selected: Camera.galleryFilter === "all"; onClicked: Camera.galleryFilter = "all" }
                Choice { text: Tr.t("Recents"); selected: Camera.galleryFilter === "recents"; onClicked: Camera.galleryFilter = "recents" }
                Choice { text: Tr.t("Favorites"); selected: Camera.galleryFilter === "favorites"; onClicked: Camera.galleryFilter = "favorites" }
                Item { Layout.fillWidth: true }
                Text {
                    text: Camera.galleryView.length + " / " + Camera.gallery.length
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: Tr.t("Showing %1 of %2 captures", Camera.galleryView.length, Camera.gallery.length)
                }
            }
            Text {
                Layout.fillWidth: true
                visible: Camera.gallery.length === 0
                text: Tr.t("No captures yet")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            Text {
                Layout.fillWidth: true
                visible: Camera.gallery.length > 0 && Camera.galleryView.length === 0
                text: Camera.galleryFilter === "favorites" ? Tr.t("No favorites yet") : Tr.t("No recent captures")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.name: text
            }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.px(320), count * Theme.px(80))
                model: Camera.galleryView
                spacing: Theme.px(4)
                delegate: Rectangle {
                    id: captureRow
                    required property var modelData
                    width: ListView.view.width
                    // the actions wrap into a second line on a phone; the row
                    // grows with them instead of clipping the tap targets
                    height: Math.max(Theme.px(44), galActions.implicitHeight + Theme.px(34))
                    radius: Theme.radiusSmall
                    color: galArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + ", " + modelData.when
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(10)
                        anchors.rightMargin: Theme.px(6)
                        anchors.topMargin: Theme.px(2)
                        anchors.bottomMargin: Theme.px(2)
                        spacing: 0
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text; elide: Text.ElideMiddle; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                            Text { Layout.fillWidth: true; text: modelData.when; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                        }
                        Flow {
                            id: galActions
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Repeater {
                                model: 5
                                IconButton {
                                    icon: captureRow.modelData.rating > index ? "starred" : "non-starred"
                                    size: Theme.px(18)
                                    tip: Tr.t("Rate %1 stars", index + 1)
                                    accessibleName: tip
                                    onClicked: Camera.rate(captureRow.modelData.path, index + 1)
                                }
                            }
                            IconButton {
                                icon: captureRow.modelData.favorite ? "starred" : "non-starred"
                                on: captureRow.modelData.favorite
                                size: Theme.px(26)
                                tip: Tr.t("Favorite capture")
                                accessibleName: tip
                                onClicked: Camera.toggleFavorite(captureRow.modelData.path)
                            }
                            IconButton { icon: "folder-publicshare"; size: Theme.px(26); tip: Tr.t("Share capture"); accessibleName: tip; onClicked: Share.open(captureRow.modelData.path) }
                            IconButton { icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy capture path"); accessibleName: tip; onClicked: Camera.copyPath(captureRow.modelData.path) }
                            IconButton { icon: "edit-delete"; size: Theme.px(26); tip: Tr.t("Delete capture"); Accessible.name: Tr.t("Delete capture"); onClicked: Camera.trash(modelData.path) }
                        }
                    }
                    MouseArea { id: galArea; anchors.fill: parent; z: -1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Viewer.open(modelData.path) }
                    KeyFocus { onActivated: Viewer.open(modelData.path) }
                }
            }
            Text {
                Layout.fillWidth: true
                text: Tr.t("Space shoot · C mode · G grid · F flash · B burst · T timer · X zoom · Z exposure · Esc close")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
                wrapMode: Text.WordWrap
                Accessible.name: text
            }
            }
        }
    }
}
