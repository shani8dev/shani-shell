// The Voice Recorder (GNOME Sound Recorder parity): a big record button,
// pause/resume, a HH:MM:SS timer and a live input level meter, over the
// recordings in ~/Music/Voice Recorder — play, rename, delete per row.
// The state lives in Services/VoiceRecorder (pw-record); this is only the
// surface, in the QrView PanelWindow pattern.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.voiceRecorder && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-voice-recorder"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string renaming: ""        // path being renamed, "" when none

    onVisibleChanged: { if (visible) VoiceRecorder.refresh(); }

    MouseArea { anchors.fill: parent; onClicked: Ui.voiceRecorder = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.voiceRecorder = false }

    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 80)
        implicitHeight: col.implicitHeight + 40
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Icon { name: "audio-input-microphone"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Voice Recorder")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "view-refresh"; size: 28; tip: Tr.t("Refresh"); onClicked: VoiceRecorder.refresh() }
                IconButton { icon: "window-close"; size: 28; tip: Tr.t("Close"); onClicked: Ui.voiceRecorder = false }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: VoiceRecorder.elapsed
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: 34 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: VoiceRecorder.paused ? Tr.t("Paused")
                    : VoiceRecorder.recording ? Tr.t("Recording")
                    : VoiceRecorder.available ? Tr.t("Ready") : Tr.t("pw-record is not installed")
                color: VoiceRecorder.recording ? Theme.red : Theme.dim
                font.family: Theme.font
                font.pixelSize: 12 * Theme.fontScale
            }

            // input level: a thin bar, peak of the last 100 ms of capture
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: Theme.hover
                visible: VoiceRecorder.recording
                Rectangle {
                    width: Math.max(4, parent.width * Math.min(1, VoiceRecorder.level))
                    height: parent.height
                    radius: 4
                    color: VoiceRecorder.level > 0.9 ? Theme.red : Theme.accent
                    Behavior on width { NumberAnimation { duration: 90 } }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 16
                IconButton {
                    icon: VoiceRecorder.paused ? "media-playback-start" : "media-playback-pause"
                    size: 44
                    tip: VoiceRecorder.paused ? Tr.t("Resume") : Tr.t("Pause")
                    visible: VoiceRecorder.recording
                    onClicked: VoiceRecorder.togglePause()
                }
                Rectangle {
                    Layout.preferredWidth: 88
                    Layout.preferredHeight: 88
                    radius: 44
                    color: VoiceRecorder.recording ? Theme.red : Theme.accent
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: VoiceRecorder.available
                        onClicked: VoiceRecorder.toggle()
                    }
                    KeyFocus {
                        name: VoiceRecorder.recording ? Tr.t("Stop recording") : Tr.t("Record")
                        onActivated: VoiceRecorder.toggle()
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: VoiceRecorder.recording ? "media-playback-stop" : "media-record"
                        size: 36
                        color: "white"
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: VoiceRecorder.recording ? Tr.t("Stop recording") : Tr.t("Record")
                    Accessible.onPressAction: VoiceRecorder.toggle()
                }
                Item { Layout.preferredWidth: 44; visible: !VoiceRecorder.recording }
            }

            Text {
                Layout.fillWidth: true
                visible: VoiceRecorder.file !== "" && VoiceRecorder.recording
                text: VoiceRecorder.file.split("/").pop()
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Recordings") }
                Text {
                    visible: VoiceRecorder.recordings.length > 0
                    text: Tr.t("%1 files", VoiceRecorder.recordings.length)
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 10 * Theme.fontScale
                }
            }

            EmptyState {
                Layout.fillWidth: true
                visible: VoiceRecorder.recordings.length === 0 && !VoiceRecorder.recording
                icon: "audio-input-microphone"
                title: Tr.t("No recordings yet")
                subtitle: Tr.t("Recordings are saved to ~/Music/Voice Recorder")
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(240, Math.max(44, VoiceRecorder.recordings.length * 48))
                visible: VoiceRecorder.recordings.length > 0
                clip: true
                spacing: 4
                model: VoiceRecorder.recordings
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 44
                    radius: 10
                    color: rowArea.containsMouse ? Theme.hover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 4
                        Icon { name: "audio-x-generic"; size: 16; color: Theme.text }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            visible: win.renaming !== row.modelData.path
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                color: Theme.text
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.when
                                color: Theme.dim
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 10 * Theme.fontScale
                            }
                        }
                        TextField {
                            id: renameField
                            Layout.fillWidth: true
                            visible: win.renaming === row.modelData.path
                            text: row.modelData.name.replace(/\.opus$/i, "")
                            label: Tr.t("Recording name")
                            onAccepted: {
                                VoiceRecorder.rename(row.modelData.path, text);
                                win.renaming = "";
                            }
                        }
                        IconButton {
                            icon: "media-playback-start"
                            size: 30
                            tip: Tr.t("Play")
                            onClicked: VoiceRecorder.play(row.modelData.path)
                        }
                        IconButton {
                            icon: "document-edit"
                            size: 30
                            tip: Tr.t("Rename")
                            onClicked: {
                                win.renaming = row.modelData.path;
                                Qt.callLater(function() { renameField.forceActiveFocus(Qt.MouseFocusReason); });
                            }
                        }
                        IconButton {
                            icon: "edit-delete"
                            size: 30
                            tip: Tr.t("Move to trash")
                            onClicked: VoiceRecorder.trash(row.modelData.path)
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        z: -1
                        onClicked: VoiceRecorder.play(row.modelData.path)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Esc closes")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
