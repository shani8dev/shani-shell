// Video Trimmer: pick a video, set start/end offsets in
// seconds, preview the selection duration and cut with ffmpeg
// (stream copy, re-encode fallback). The state lives in Services/Trim;
// this is only the surface, in the QrView PanelWindow pattern.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Video Trimmer"
    visible: Ui.videoTrimmer
    onGone: Ui.videoTrimmer = false
    margins: 0
    implicitWidth: Theme.px(560)
    implicitHeight: Math.max(320, Math.min(900, col.implicitHeight + 40))

    property string manualPath: ""
    readonly property real span: VideoTrimmer.inputDuration > 0 ? VideoTrimmer.inputDuration : 60

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Ui.videoTrimmer = false
        Keys.onPressed: e => {
            if (e.key === Qt.Key_I) { VideoTrimmer.markIn(); e.accepted = true; }
            else if (e.key === Qt.Key_O) { VideoTrimmer.markOut(); e.accepted = true; }
            else if (e.key === Qt.Key_S) { VideoTrimmer.splitAtPlayhead(); e.accepted = true; }
            else if (e.key === Qt.Key_Left) { VideoTrimmer.nudgePlayhead(-VideoTrimmer.frameStep); e.accepted = true; }
            else if (e.key === Qt.Key_Right) { VideoTrimmer.nudgePlayhead(VideoTrimmer.frameStep); e.accepted = true; }
        }
    }

    // made on first use: a native dialog is the desktop portal's, and made
    // with every picker it held the whole shell while D-Bus waited for it
    Loader {
        id: videoDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Choose a video to trim")
            nameFilters: [Tr.t("Video files") + " (*.mp4 *.webm *.mov *.mkv *.avi)"]
            onAccepted: VideoTrimmer.open(selectedFile.toString().replace(/^file:\/\//, ""))
        }
    }

    Item {
        id: blurCard
        anchors.fill: parent

        ColumnLayout {
            id: col
            x: 20
            y: 20
            width: parent.width - 40
            spacing: Theme.px(12)

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Text {
                    visible: !VideoTrimmer.available
                    text: Tr.t("ffmpeg is not installed")
                    color: Theme.red
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }

            // the input video: file arg, folder's last video, or pick one
            Text {
                Layout.fillWidth: true
                text: Tr.t("Input video")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.px(36)
                    radius: Theme.px(8)
                    color: Theme.surface1
                    border.color: Theme.stroke
                    border.width: 1
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(10)
                        anchors.rightMargin: Theme.px(10)
                        verticalAlignment: Text.AlignVCenter
                        text: VideoTrimmer.input === "" ? Tr.t("No video — pick one") : VideoTrimmer.input
                        color: VideoTrimmer.input === "" ? Theme.faint : Theme.text
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(10) * Theme.fontScale
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
                spacing: Theme.px(8)
                TextField {
                    id: pathField
                    Layout.fillWidth: true
                    text: win.manualPath
                    placeholder: Tr.t("… or paste a video or folder path")
                    label: Tr.t("Video path")
                    onAccepted: VideoTrimmer.open(pathField.text.trim())
                }
                Button {
                    text: Tr.t("Load")
                    onClicked: VideoTrimmer.open(pathField.text.trim())
                }
            }

            // duration preview: the whole file and the chosen selection
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: VideoTrimmer.inputDuration > 0
                    ? Tr.t("Duration %1 · Selection %2").arg(VideoTrimmer.fmt(VideoTrimmer.inputDuration)).arg(VideoTrimmer.selectionText || "--")
                    : Tr.t("Duration unknown — set start and end in seconds")
                color: Theme.faint
                font.family: Theme.mono
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }

            // start offset: slider + seconds field + -1s / +1s
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                SliderRow {
                    Layout.fillWidth: true
                    icon: "go-previous"
                    value: win.span > 0 ? VideoTrimmer.start / win.span : 0
                    onMoved: v => VideoTrimmer.setStart(v * win.span)
                }
                Button { text: "-1s"; onClicked: VideoTrimmer.nudgeStart(-1) }
                Button { text: "+1s"; onClicked: VideoTrimmer.nudgeStart(1) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text {
                    text: Tr.t("Start")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                TextField {
                    id: startField
                    Layout.fillWidth: true
                    text: VideoTrimmer.start.toFixed(1)
                    placeholder: "0.0"
                    label: Tr.t("Start offset (seconds)")
                    onAccepted: VideoTrimmer.setStart(parseFloat(startField.text))
                }
            }

            // end offset
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                SliderRow {
                    Layout.fillWidth: true
                    icon: "go-next"
                    value: win.span > 0 ? VideoTrimmer.end / win.span : 0
                    onMoved: v => VideoTrimmer.setEnd(v * win.span)
                }
                Button { text: "-1s"; onClicked: VideoTrimmer.nudgeEnd(-1) }
                Button { text: "+1s"; onClicked: VideoTrimmer.nudgeEnd(1) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text {
                    text: Tr.t("End")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                TextField {
                    id: endField
                    Layout.fillWidth: true
                    text: VideoTrimmer.end.toFixed(1)
                    placeholder: "0.0"
                    label: Tr.t("End offset (seconds)")
                    onAccepted: VideoTrimmer.setEnd(parseFloat(endField.text))
                }
            }

            // ---- playhead: frame stepping and I / O / S shortcuts ------------
            SectionTitle { Layout.fillWidth: true; text: Tr.t("Playhead") + "  ·  " + VideoTrimmer.fmt(VideoTrimmer.playhead) }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button { text: "◀"; flat: true; enabled: VideoTrimmer.inputDuration > 0; Accessible.name: Tr.t("One frame back"); onClicked: VideoTrimmer.nudgePlayhead(-VideoTrimmer.frameStep) }
                SliderRow {
                    Layout.fillWidth: true
                    icon: "go-next"
                    value: VideoTrimmer.inputDuration > 0 ? VideoTrimmer.playhead / VideoTrimmer.inputDuration : 0
                    onMoved: v => VideoTrimmer.setPlayhead(v * win.span)
                }
                Button { text: "▶"; flat: true; enabled: VideoTrimmer.inputDuration > 0; Accessible.name: Tr.t("One frame forward"); onClicked: VideoTrimmer.nudgePlayhead(VideoTrimmer.frameStep) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button { text: Tr.t("In (I)"); onClicked: VideoTrimmer.markIn() }
                Button { text: Tr.t("Out (O)"); onClicked: VideoTrimmer.markOut() }
                Button { text: Tr.t("Split (S)"); onClicked: VideoTrimmer.splitAtPlayhead() }
                Button { text: Tr.t("Capture frame"); onClicked: VideoTrimmer.captureFrame() }
            }
            Text {
                Layout.fillWidth: true
                visible: VideoTrimmer.frameCaptured !== "" || VideoTrimmer.captureError !== ""
                text: VideoTrimmer.captureError !== "" ? VideoTrimmer.captureError : Tr.t("Saved") + " " + VideoTrimmer.frameCaptured
                color: VideoTrimmer.captureError !== "" ? Theme.red : Theme.text
                elide: Text.ElideMiddle
                font.family: Theme.mono
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }

            // ---- multiple segments to join on export -------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Segments") + "  ·  " + VideoTrimmer.segments.length }
                Button { text: Tr.t("Add selection"); enabled: VideoTrimmer.end > VideoTrimmer.start; onClicked: VideoTrimmer.addSegment(VideoTrimmer.start, VideoTrimmer.end) }
                Button { text: Tr.t("Clear"); flat: true; enabled: VideoTrimmer.segments.length > 0; onClicked: VideoTrimmer.clearSegments() }
            }
            Repeater {
                model: VideoTrimmer.segments
                RowLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Text { Layout.fillWidth: true; text: Tr.t("Segment %1").arg(index + 1) + "  ·  " + VideoTrimmer.fmt(modelData.start) + " – " + VideoTrimmer.fmt(modelData.end); color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    IconButton { icon: "list-remove"; size: Theme.px(24); Accessible.name: Tr.t("Remove segment"); onClicked: VideoTrimmer.removeSegment(index) }
                }
            }
            Button {
                Layout.alignment: Qt.AlignHCenter
                text: VideoTrimmer.cutting ? Tr.t("Joining…") : Tr.t("Cut and join segments")
                enabled: !VideoTrimmer.cutting && VideoTrimmer.segments.length >= 2 && VideoTrimmer.available
                onClicked: VideoTrimmer.cutSegments()
            }

            // ---- progress and cancel for a running cut -----------------------
            RowLayout {
                Layout.fillWidth: true
                visible: VideoTrimmer.cutting
                spacing: Theme.px(8)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(8)
                    radius: Theme.px(4)
                    color: Theme.surface3
                    Rectangle { width: parent.width * VideoTrimmer.progress; height: parent.height; radius: Theme.px(4); color: Theme.accent }
                }
                Text { text: Math.round(VideoTrimmer.progress * 100) + "%"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Button { text: Tr.t("Cancel"); kind: "danger"; onClicked: VideoTrimmer.cancelCut() }
            }

            Button {
                Layout.alignment: Qt.AlignHCenter
                text: VideoTrimmer.cutting ? Tr.t("Cutting…") : Tr.t("Cut")
                kind: "primary"
                enabled: VideoTrimmer.input !== "" && !VideoTrimmer.cutting && VideoTrimmer.end > VideoTrimmer.start && VideoTrimmer.available
                onClicked: VideoTrimmer.cut()
            }

            Text {
                Layout.fillWidth: true
                visible: VideoTrimmer.error !== ""
                text: VideoTrimmer.error
                color: Theme.red
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }

            // the result: path, output duration via ffprobe when present,
            // and Open / Trash
            ColumnLayout {
                Layout.fillWidth: true
                visible: VideoTrimmer.result !== ""
                spacing: Theme.px(6)
                Text {
                    Layout.fillWidth: true
                    text: VideoTrimmer.result
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                    elide: Text.ElideMiddle
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: VideoTrimmer.resultDuration >= 0
                    text: Tr.t("Output %1").arg(VideoTrimmer.fmt(VideoTrimmer.resultDuration))
                    color: Theme.faint
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.px(8)
                    Button { text: Tr.t("Open"); onClicked: VideoTrimmer.openResult() }
                    Button { text: Tr.t("Trash"); kind: "danger"; onClicked: VideoTrimmer.trashResult() }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Esc closes · -1s / +1s step the offsets")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
    }
}
