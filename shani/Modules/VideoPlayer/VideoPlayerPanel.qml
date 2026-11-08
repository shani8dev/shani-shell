// VideoPlayer (VideoPlayer): opens video files with GStreamer (gst-play-1.0).
// Replaces org.gnome.Showtime for everyday video playback. GStreamer is
// the engine because Qt6Multimedia is not available in this shell.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import qs.Common
import qs.Services as Services

PanelWindow {
    id: win
    visible: Ui.videoPlayer && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Services.Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-videoplayer"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var recentFiles: []
    property string currentFile: ""

    MouseArea { anchors.fill: parent; onClicked: Ui.videoPlayer = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 600)
        height: Math.min(parent.height - 60, 500)
        radius: Theme.radiusLg

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Label { text: "Video Player"; font.bold: true; font.pixelSize: 18 }

            Label { text: "GStreamer (gst-play-1.0) is the playback engine (QtMultimedia unavailable)."; font.pixelSize: 11; color: Theme.onSurfaceVariant; wrapMode: Text.Wrap; Layout.fillWidth: true }

            Button {
                Layout.fillWidth: true
                text: "Open video file…"
                onClicked: fileDialog.open()
            }

            Label { text: "Recent files:"; font.pixelSize: 12; color: Theme.onSurfaceVariant }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: win.recentFiles
                delegate: ItemDelegate {
                    width: parent.width
                    text: modelData.split("/").pop()
                    onClicked: { win.currentFile = modelData; launchPlayer(modelData); }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Button { text: "Play with GStreamer"; enabled: win.currentFile !== ""; onClicked: launchPlayer(win.currentFile) }
                Button { text: "Close"; onClicked: Ui.videoPlayer = false }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: "Open video"
        nameFilters: ["Video files (*.mp4 *.mkv *.avi *.webm *.mov *.m4v)", "All files (*)"]
        onAccepted: {
            const path = fileDialog.selectedFile.toString().replace("file://", "");
            win.currentFile = path;
            if (win.recentFiles.indexOf(path) < 0) win.recentFiles = [path].concat(win.recentFiles).slice(0, 20);
            launchPlayer(path);
        }
    }

    function launchPlayer(path) {
        // Prefer gst-play-1.0 (GStreamer, always available), fall back to mpv
        if (gstProc.running) gstProc.running = false;
        gstProc.command = ["gst-play-1.0", path];
        gstProc.running = true;
    }

    Process {
        id: gstProc
        running: false
        onExited: { /* player closed */ }
    }

    Keys.onEscapePressed: Ui.videoPlayer = false
}
