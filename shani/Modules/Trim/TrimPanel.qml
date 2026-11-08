// Omacut: the video trimmer — pick a video, set start/end offsets in
// seconds, preview the selection duration and cut with ffmpeg
// (stream copy, re-encode fallback). The state lives in Services/Trim;
// this is only the surface, in the QrView PanelWindow pattern.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.trim && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-trim"
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string manualPath: ""
    readonly property real span: Trim.inputDuration > 0 ? Trim.inputDuration : 60

    MouseArea { anchors.fill: parent; onClicked: Ui.trim = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.trim = false }

    // made on first use: a native dialog is the desktop portal's, and made
    // with every picker it held the whole shell while D-Bus waited for it
    Loader {
        id: videoDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Choose a video to trim")
            nameFilters: [Tr.t("Video files") + " (*.mp4 *.webm *.mov *.mkv *.avi)"]
            onAccepted: Trim.open(selectedFile.toString().replace(/^file:\/\//, ""))
        }
    }

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
                Icon { name: "video-x-generic"; size: 20; color: Theme.accent }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Video trimmer")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: !Trim.available
                    text: Tr.t("ffmpeg is not installed")
                    color: Theme.red
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                IconButton { icon: "window-close"; size: 28; tip: Tr.t("Close"); onClicked: Ui.trim = false }
            }

            // the input video: file arg, folder's last video, or pick one
            Text {
                Layout.fillWidth: true
                text: Tr.t("Input video")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 8
                    color: Theme.surface1
                    border.color: Theme.stroke
                    border.width: 1
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        text: Trim.input === "" ? Tr.t("No video — pick one") : Trim.input
                        color: Trim.input === "" ? Theme.faint : Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 10 * Theme.fontScale
                        elide: Text.ElideMiddle
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Tr.t("Input video")
                    }
                }
                Button {
                    text: Tr.t("Browse")
                    onClicked: videoDlg.open()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: pathField
                    Layout.fillWidth: true
                    text: win.manualPath
                    placeholder: Tr.t("… or paste a video or folder path")
                    label: Tr.t("Video path")
                    onAccepted: Trim.open(pathField.text.trim())
                }
                Button {
                    text: Tr.t("Load")
                    onClicked: Trim.open(pathField.text.trim())
                }
            }

            // duration preview: the whole file and the chosen selection
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Trim.inputDuration > 0
                    ? Tr.t("Duration %1 · Selection %2").arg(Trim.fmt(Trim.inputDuration)).arg(Trim.selectionText || "--")
                    : Tr.t("Duration unknown — set start and end in seconds")
                color: Theme.faint
                font.family: Theme.mono
                font.pixelSize: 11 * Theme.fontScale
            }

            // start offset: slider + seconds field + -1s / +1s
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SliderRow {
                    Layout.fillWidth: true
                    icon: "go-previous"
                    value: win.span > 0 ? Trim.start / win.span : 0
                    onMoved: v => Trim.setStart(v * win.span)
                }
                Button { text: "-1s"; onClicked: Trim.nudgeStart(-1) }
                Button { text: "+1s"; onClicked: Trim.nudgeStart(1) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: Tr.t("Start")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                TextField {
                    id: startField
                    Layout.fillWidth: true
                    text: Trim.start.toFixed(1)
                    placeholder: "0.0"
                    label: Tr.t("Start offset (seconds)")
                    onAccepted: Trim.setStart(parseFloat(startField.text))
                }
            }

            // end offset
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SliderRow {
                    Layout.fillWidth: true
                    icon: "go-next"
                    value: win.span > 0 ? Trim.end / win.span : 0
                    onMoved: v => Trim.setEnd(v * win.span)
                }
                Button { text: "-1s"; onClicked: Trim.nudgeEnd(-1) }
                Button { text: "+1s"; onClicked: Trim.nudgeEnd(1) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: Tr.t("End")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                TextField {
                    id: endField
                    Layout.fillWidth: true
                    text: Trim.end.toFixed(1)
                    placeholder: "0.0"
                    label: Tr.t("End offset (seconds)")
                    onAccepted: Trim.setEnd(parseFloat(endField.text))
                }
            }

            Button {
                Layout.alignment: Qt.AlignHCenter
                text: Trim.cutting ? Tr.t("Cutting…") : Tr.t("Cut")
                kind: "primary"
                enabled: Trim.input !== "" && !Trim.cutting && Trim.end > Trim.start && Trim.available
                onClicked: Trim.cut()
            }

            Text {
                Layout.fillWidth: true
                visible: Trim.error !== ""
                text: Trim.error
                color: Theme.red
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }

            // the result: path, output duration via ffprobe when present,
            // and Open / Trash
            ColumnLayout {
                Layout.fillWidth: true
                visible: Trim.result !== ""
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: Trim.result
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: 10 * Theme.fontScale
                    elide: Text.ElideMiddle
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: Trim.resultDuration >= 0
                    text: Tr.t("Output %1").arg(Trim.fmt(Trim.resultDuration))
                    color: Theme.faint
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.mono
                    font.pixelSize: 11 * Theme.fontScale
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    Button { text: Tr.t("Open"); onClicked: Trim.openResult() }
                    Button { text: Tr.t("Trash"); kind: "danger"; onClicked: Trim.trashResult() }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Esc closes · -1s / +1s step the offsets")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
