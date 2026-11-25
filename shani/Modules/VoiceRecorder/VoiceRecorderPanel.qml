// The Voice Recorder (GNOME Sound Recorder parity): a big record button,
// pause/resume, a HH:MM:SS timer and a live input level meter, over the
// recordings in ~/Music/Voice Recorder — play, rename, delete per row.
// The state lives in Services/VoiceRecorder (pw-record); this is only the
// surface, in the QrView PanelWindow pattern.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Voice Recorder"
    tools: [
        IconButton { size: Theme.px(30); icon: "view-refresh"; tip: Tr.t("Refresh"); onClicked: VoiceRecorder.refresh() }
    ]
    visible: Ui.voiceRecorder
    onGone: Ui.voiceRecorder = false
    margins: 0
    implicitWidth: Theme.px(560)
    implicitHeight: Math.max(320, Math.min(900, col.implicitHeight + 80))

    property string renaming: ""        // path being renamed, "" when none
    property string inlinePlay: ""      // take playing in the panel itself
    property string confirmingDelete: "" // take waiting for a second click before trash
    property string search: ""          // recordings list filter
    property int sortMode: 0            // 0 newest, 1 oldest, 2 name

    // ---- persistent waveform peaks ----------------------------------------
    // The bridge decodes a take once and caches a bounded peak array in a
    // sibling .peaks.json; the panel asks only when a take is played here, so
    // an unused recording never costs a decode. Peaks are the real audio's,
    // not the live level meter's - that one is only a 100 ms snapshot.
    readonly property string waveformTool: Quickshell.env("SHANI_WAVEFORM_TOOL") || "/usr/lib/shani-shell/waveform.py"
    property var peaks: []              // <= 256 amplitudes in 0..1
    property string peaksFor: ""        // the path `peaks` belongs to
    property bool peaksLoading: false
    function loadPeaks(path) {
        if (!path || !waveformTool || win.peaksFor === path)
            return;
        win.peaks = [];
        win.peaksFor = path;
        win.peaksLoading = true;
        peakProc.running = false;
        peakProc.command = ["python3", waveformTool, path];
        peakProc.running = true;
    }
    Process {
        id: peakProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                if (d && Array.isArray(d.peaks) && d.peaks.length)
                    win.peaks = d.peaks.slice(0, 256).map(v => Math.max(0, Math.min(1, parseFloat(v) || 0)));
            }
        }
        onExited: win.peaksLoading = false
    }
    // a trashed take leaves no cached peaks behind
    Process { id: dropPeaks }
    function dropCachedPeaks(path) {
        if (!path) return;
        if (win.peaksFor === path) { peakProc.running = false; win.peaks = []; win.peaksFor = ""; }
        dropPeaks.command = ["rm", "-f", "--", path + ".peaks.json"];
        dropPeaks.running = true;
    }

    // Voice Memos and Sound Recorder never trash a take on one accidental
    // click, and both let a long list be searched and re-sorted. The service
    // keeps the raw newest-first list; the filter/sort is view-only.
    function trashTake(path) {
        if (!path) return;
        if (win.inlinePlay === path) { playback.stop(); win.inlinePlay = ""; }
        if (win.renaming === path) win.renaming = "";
        if (win.confirmingDelete === path) win.confirmingDelete = "";
        win.dropCachedPeaks(path);
        VoiceRecorder.trash(path);
    }
    function visibleRows() {
        const needle = win.search.trim().toLowerCase();
        const rows = VoiceRecorder.recordings.filter(r => !needle || String(r.name || "").toLowerCase().indexOf(needle) >= 0);
        if (win.sortMode === 1) return rows.slice().reverse();
        if (win.sortMode === 2) return rows.slice().sort((a, b) => String(a.name).localeCompare(String(b.name)));
        return rows;
    }

    // in-app playback, instead of always handing the file to another app
    MediaPlayer {
        id: playback
        audioOutput: AudioOutput {}
        // a take that ended (or failed to load) must not leave a dead bar behind
        onMediaStatusChanged: {
            if (playback.mediaStatus === MediaPlayer.EndOfMedia || playback.mediaStatus === MediaPlayer.InvalidMedia)
                win.inlinePlay = "";
        }
    }
    function playInline(path) {
        if (!path) return;
        if (win.inlinePlay === path && playback.playbackState === MediaPlayer.PlayingState) {
            playback.pause();
            return;
        }
        playback.stop();
        playback.source = "file://" + encodeURI(path);
        win.inlinePlay = path;
        win.loadPeaks(path);
        playback.play();
        // the panel is smaller than its content once the bar appears: scroll
        // down so the waveform and controls are visible without a manual flick
        Qt.callLater(() => contentScroll.contentY = Math.max(0, contentScroll.contentHeight - contentScroll.height));
    }
    // a take can be handed to the full player as well as played in this panel;
    // close the panel so the player is not left behind it, and let the panel's
    // own playback stop with it rather than fighting the player for the audio
    function openInPlayer(path) {
        if (!path) return;
        Ui.voiceRecorder = false;
        PlayQueue.open(path);
    }
    function exportDialog(path) {
        FilePicker.open({
            mode: "save",
            defaultName: (path || "recording").split("/").pop().replace(/\.(opus|flac)$/i, "") + ".opus",
            filters: ["opus", "flac", "wav"],
            title: Tr.t("Export recording…"),
            onPicked: paths => { if (paths.length) VoiceRecorder.exportTo(paths[0], path); }
        });
    }

    onVisibleChanged: { if (visible) VoiceRecorder.refresh(); else { playback.stop(); win.inlinePlay = ""; } }

    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.voiceRecorder = false }

    Item {
        id: blurCard
        anchors.fill: parent

        Flickable {
            id: contentScroll
            anchors.fill: parent
            anchors.margins: Theme.px(20)
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: col.implicitHeight
            ColumnLayout {
                id: col
                width: parent.width
                spacing: Theme.px(12)


            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: VoiceRecorder.elapsed
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: Theme.px(34) * Theme.fontScale
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
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }

            // codec and channels, chosen before the next take
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.px(8)
                Text { text: Tr.t("Format"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: "Opus"; selected: VoiceRecorder.format === "opus"; onClicked: VoiceRecorder.format = "opus" }
                Choice { text: "FLAC"; selected: VoiceRecorder.format === "flac"; onClicked: VoiceRecorder.format = "flac" }
                Text { text: Tr.t("Channels"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Choice { text: Tr.t("Mono"); selected: VoiceRecorder.channels === 1; onClicked: VoiceRecorder.channels = 1 }
                Choice { text: Tr.t("Stereo"); selected: VoiceRecorder.channels === 2; onClicked: VoiceRecorder.channels = 2 }
            }

            // input level: a thin bar, peak of the last 100 ms of capture
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(8)
                radius: Theme.px(4)
                color: Theme.hover
                visible: VoiceRecorder.recording
                Rectangle {
                    width: Math.max(4, parent.width * Math.min(1, VoiceRecorder.level))
                    height: parent.height
                    radius: Theme.px(4)
                    color: VoiceRecorder.level > 0.9 ? Theme.red : Theme.accent
                    Behavior on width { NumberAnimation { duration: Theme.mot(90) } }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.px(16)
                IconButton {
                    icon: VoiceRecorder.paused ? "media-playback-start" : "media-playback-pause"
                    size: Theme.px(44)
                    tip: VoiceRecorder.paused ? Tr.t("Resume") : Tr.t("Pause")
                    visible: VoiceRecorder.recording
                    onClicked: VoiceRecorder.togglePause()
                }
                IconButton {
                    icon: "edit-delete"
                    size: Theme.px(36)
                    tip: Tr.t("Discard take")
                    Accessible.name: Tr.t("Discard take")
                    visible: VoiceRecorder.recording
                    onClicked: VoiceRecorder.cancel()
                }
                Rectangle {
                    Layout.preferredWidth: Theme.px(88)
                    Layout.preferredHeight: Theme.px(88)
                    radius: Theme.px(44)
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
                        size: Theme.px(36)
                        color: "white"
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: VoiceRecorder.recording ? Tr.t("Stop recording") : Tr.t("Record")
                    Accessible.onPressAction: VoiceRecorder.toggle()
                }
                Item { Layout.preferredWidth: Theme.px(44); visible: !VoiceRecorder.recording }
            }

            Text {
                Layout.fillWidth: true
                visible: VoiceRecorder.file !== "" && VoiceRecorder.recording
                text: VoiceRecorder.file.split("/").pop()
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Recordings") }
                Text {
                    visible: VoiceRecorder.recordings.length > 0
                    text: Tr.t("%1 files", VoiceRecorder.recordings.length)
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                Button {
                    text: win.sortMode === 0 ? Tr.t("Sort: Newest") : win.sortMode === 1 ? Tr.t("Sort: Oldest") : Tr.t("Sort: Name")
                    flat: true
                    onClicked: win.sortMode = (win.sortMode + 1) % 3
                }
            }

            TextField {
                Layout.fillWidth: true
                id: searchField
                text: win.search
                placeholder: Tr.t("Search recordings")
                label: Tr.t("Search recordings")
                onTextChanged: win.search = text
                Keys.onEscapePressed: { if (text !== "") { event.accepted = true; text = ""; } }
            }

            EmptyState {
                Layout.fillWidth: true
                visible: VoiceRecorder.recordings.length === 0 && !VoiceRecorder.recording
                icon: "audio-input-microphone"
                title: Tr.t("No recordings yet")
                subtitle: Tr.t("Recordings are saved to ~/Music/Voice Recorder")
            }
            EmptyState {
                Layout.fillWidth: true
                visible: win.search !== "" && VoiceRecorder.recordings.length > 0 && win.visibleRows().length === 0
                icon: "edit-find"
                title: Tr.t("No matching recordings")
                subtitle: Tr.t("Try a different search")
            }

            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(240, Math.max(44, win.visibleRows().length * 48))
                visible: win.visibleRows().length > 0
                clip: true
                spacing: Theme.px(4)
                model: win.visibleRows()
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: Theme.px(44)
                    radius: Theme.px(10)
                    color: rowArea.containsMouse ? Theme.hover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(10)
                        anchors.rightMargin: Theme.px(6)
                        spacing: Theme.px(4)
                        Icon { name: "audio-x-generic"; size: Theme.px(16); color: Theme.text }
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
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (row.modelData.when || Tr.t("Recording")) + (row.modelData.duration > 0 ? "  ·  " + VideoTrimmer.fmt(row.modelData.duration) : "")
                                color: Theme.dim
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: Theme.px(10) * Theme.fontScale
                            }
                        }
                        TextField {
                            id: renameField
                            Layout.fillWidth: true
                            visible: win.renaming === row.modelData.path
                            text: row.modelData.name.replace(/\.opus$/i, "")
                            label: Tr.t("Recording name")
                            // Escape cancels the rename here; it must not reach
                            // the window's Escape handler and close the panel
                            Keys.onEscapePressed: { event.accepted = true; win.renaming = ""; }
                            onAccepted: {
                                if (win.inlinePlay === row.modelData.path) { playback.stop(); win.inlinePlay = ""; }
                                VoiceRecorder.rename(row.modelData.path, text);
                                win.renaming = "";
                            }
                        }
                        IconButton {
                            icon: win.inlinePlay === row.modelData.path && playback.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                            size: Theme.px(30)
                            tip: Tr.t("Play here")
                            Accessible.name: Tr.t("Play in the recorder")
                            onClicked: win.playInline(row.modelData.path)
                        }
                        IconButton {
                            icon: "applications-multimedia"
                            size: Theme.px(30)
                            tip: Tr.t("Open in %1", "Media Player")
                            Accessible.name: Tr.t("Open in %1", "Media Player")
                            onClicked: win.openInPlayer(row.modelData.path)
                        }
                        IconButton {
                            icon: "document-save-as"
                            size: Theme.px(30)
                            tip: Tr.t("Export…")
                            Accessible.name: Tr.t("Export recording")
                            onClicked: win.exportDialog(row.modelData.path)
                        }
                        IconButton {
                            icon: "document-edit"
                            size: Theme.px(30)
                            tip: Tr.t("Rename")
                            onClicked: {
                                win.renaming = row.modelData.path;
                                Qt.callLater(function() { renameField.forceActiveFocus(Qt.MouseFocusReason); });
                            }
                        }
                        IconButton {
                            icon: "edit-cut"
                            size: Theme.px(30)
                            tip: Tr.t("Trim take")
                            onClicked: VoiceRecorder.openTrim(row.modelData.path)
                        }
                        IconButton {
                            icon: "edit-delete"
                            size: Theme.px(30)
                            tip: win.confirmingDelete === row.modelData.path ? Tr.t("Tap again to trash") : Tr.t("Move to trash")
                            onClicked: {
                                if (win.confirmingDelete === row.modelData.path) win.trashTake(row.modelData.path);
                                else win.confirmingDelete = row.modelData.path;
                            }
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

            RowLayout {
                Layout.fillWidth: true
                visible: win.confirmingDelete !== ""
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Move %1 to trash?").arg(win.confirmingDelete.split("/").pop())
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: win.confirmingDelete = "" }
                Button { text: Tr.t("Trash"); kind: "danger"; onClicked: win.trashTake(win.confirmingDelete) }
            }

            // Monologue-style take trim: two sliders on the take, then a
            // trimmed copy (*.trimmed.opus) via the Trim service's audio
            // branch (ffmpeg re-encodes libopus).
            ColumnLayout {
                Layout.fillWidth: true
                visible: VoiceRecorder.trimFile !== ""
                spacing: Theme.px(6)
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Trim take") }
                Text {
                    Layout.fillWidth: true
                    text: VoiceRecorder.trimFile.split("/").pop()
                    color: Theme.dim
                    elide: Text.ElideMiddle
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                SliderRow {
                    Layout.fillWidth: true
                    icon: "go-previous"
                    onIconClicked: () => VoiceRecorder.setTrimStart(VoiceRecorder.trimStart - 1)
                    value: VoiceRecorder.trimDuration > 0 ? VoiceRecorder.trimStart / VoiceRecorder.trimDuration : 0
                    onMoved: v => VoiceRecorder.setTrimStart(v * (VoiceRecorder.trimDuration > 0 ? VoiceRecorder.trimDuration : 60))
                }
                SliderRow {
                    Layout.fillWidth: true
                    icon: "go-next"
                    onIconClicked: () => VoiceRecorder.setTrimEnd(VoiceRecorder.trimEnd + 1)
                    value: VoiceRecorder.trimDuration > 0 ? (VoiceRecorder.trimEnd > 0 ? VoiceRecorder.trimEnd : VoiceRecorder.trimDuration) / VoiceRecorder.trimDuration : 0
                    onMoved: v => VoiceRecorder.setTrimEnd(v * (VoiceRecorder.trimDuration > 0 ? VoiceRecorder.trimDuration : 60))
                }
                // exact in/out entry plus a tenth-of-a-second step: a slider is
                // fine for a rough cut, not for the first seconds of a voice note
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Text { text: Tr.t("In"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    TextField {
                        Layout.fillWidth: true
                        text: VoiceRecorder.trimStart.toFixed(1)
                        label: Tr.t("Trim start (seconds)")
                        onAccepted: VoiceRecorder.setTrimStart(parseFloat(text))
                    }
                    Button { text: "-0.1s"; onClicked: VoiceRecorder.setTrimStart(VoiceRecorder.trimStart - 0.1) }
                    Button { text: "+0.1s"; onClicked: VoiceRecorder.setTrimStart(VoiceRecorder.trimStart + 0.1) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Text { text: Tr.t("Out"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                    TextField {
                        Layout.fillWidth: true
                        text: (VoiceRecorder.trimEnd > 0 ? VoiceRecorder.trimEnd : VoiceRecorder.trimDuration).toFixed(1)
                        label: Tr.t("Trim end (seconds)")
                        onAccepted: VoiceRecorder.setTrimEnd(parseFloat(text))
                    }
                    Button { text: "-0.1s"; onClicked: VoiceRecorder.setTrimEnd(VoiceRecorder.trimEnd - 0.1) }
                    Button { text: "+0.1s"; onClicked: VoiceRecorder.setTrimEnd(VoiceRecorder.trimEnd + 0.1) }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: VoiceRecorder.trimDuration > 0
                        ? Tr.t("Selection %1 – %2").arg(VideoTrimmer.fmt(VoiceRecorder.trimStart)).arg(VideoTrimmer.fmt(VoiceRecorder.trimEnd > 0 ? VoiceRecorder.trimEnd : VoiceRecorder.trimDuration))
                        : Tr.t("Duration unknown — drag the sliders")
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.px(8)
                    Button { text: "-1s"; onClicked: VoiceRecorder.setTrimStart(VoiceRecorder.trimStart - 1) }
                    Button { text: "+1s"; onClicked: VoiceRecorder.setTrimStart(VoiceRecorder.trimStart + 1) }
                }
                Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: VideoTrimmer.cutting ? Tr.t("Saving…") : Tr.t("Save trimmed copy")
                    kind: "primary"
                    enabled: VoiceRecorder.trimFile !== "" && !VideoTrimmer.cutting
                    onClicked: VoiceRecorder.saveTrimmedCopy()
                }
                BusyNote {
                    Layout.alignment: Qt.AlignHCenter
                    visible: VideoTrimmer.cutting
                    note: Tr.t("Saving…")
                    iconSize: Theme.px(18)
                }
                Text {
                    Layout.fillWidth: true
                    visible: VoiceRecorder.trimError !== ""
                    text: VoiceRecorder.trimError
                    color: Theme.red
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Text {
                    Layout.fillWidth: true
                    visible: VoiceRecorder.trimmedLast !== ""
                    text: VoiceRecorder.trimmedLast
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }

            // The recorded waveform: cached peaks for this take, with a
            // playhead. Click anywhere to seek; Left / Right step five seconds.
            // No card behind it - these are just bars over the panel's surface.
            ColumnLayout {
                Layout.fillWidth: true
                visible: win.inlinePlay !== "" && win.peaks.length > 0
                spacing: Theme.px(2)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    IconButton {
                        icon: playback.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                        tip: playback.playbackState === MediaPlayer.PlayingState ? Tr.t("Pause") : Tr.t("Play")
                        size: Theme.px(26)
                        onClicked: win.playInline(win.inlinePlay)
                    }
                    Item {
                        id: wave
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(40)
                        readonly property real progress: playback.duration > 0 ? Math.max(0, Math.min(1, playback.position / playback.duration)) : 0
                        property real value: progress
                        Accessible.role: Accessible.Slider
                        Accessible.name: Tr.t("Waveform — seek in recording")
                        Row {
                            anchors.fill: parent
                            spacing: 1
                            Repeater {
                                model: win.peaks
                                Rectangle {
                                    width: Math.max(1, wave.width / Math.max(1, win.peaks.length) - 1)
                                    height: Math.max(2, (wave.height - 4) * Math.max(0, Math.min(1, modelData || 0)))
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 1
                                    color: index / Math.max(1, win.peaks.length) <= wave.progress
                                        ? Theme.accent : Theme.alpha(Theme.accent, 0.35)
                                }
                            }
                        }
                        Rectangle {
                            x: wave.progress * Math.max(0, parent.width - 2)
                            width: 2
                            height: parent.height
                            color: Theme.text
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function seekAt(x) {
                                if (playback.duration > 0)
                                    playback.setPosition(Math.max(0, Math.min(1, x / width)) * playback.duration);
                            }
                            onPressed: m => seekAt(m.x)
                            onPositionChanged: m => { if (pressed) seekAt(m.x); }
                        }
                        KeyFocus {
                            name: Tr.t("Waveform — seek in recording")
                            slider: true
                            onStep: dir => {
                                if (playback.duration > 0)
                                    playback.setPosition(Math.max(0, Math.min(playback.duration, playback.position + dir * 5000)));
                            }
                        }
                    } // wave Item
                    IconButton {
                        icon: "media-playback-stop"
                        tip: Tr.t("Stop")
                        size: Theme.px(26)
                        onClicked: { playback.stop(); win.inlinePlay = ""; }
                    }
                } // waveform controls row
                BusyNote {
                    Layout.fillWidth: true
                    visible: win.peaksLoading
                    note: Tr.t("Reading waveform…")
                }
            }

            // in-app playback bar and export feedback
            RowLayout {
                Layout.fillWidth: true
                visible: win.inlinePlay !== ""
                spacing: Theme.px(8)
                IconButton {
                    icon: playback.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                    tip: playback.playbackState === MediaPlayer.PlayingState ? Tr.t("Pause") : Tr.t("Play")
                    size: Theme.px(28)
                    onClicked: win.playInline(win.inlinePlay)
                }
                Text { Layout.fillWidth: true; text: win.inlinePlay.split("/").pop(); color: Theme.text; elide: Text.ElideMiddle; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                SliderRow {
                    Layout.fillWidth: true
                    label: Tr.t("Seek in recording")
                    icon: "go-next"
                    value: playback.duration > 0 ? playback.position / playback.duration : 0
                    onMoved: v => { if (playback.duration > 0) playback.setPosition(v * playback.duration); }
                }
                Text {
                    text: VideoTrimmer.fmt(playback.position / 1000) + " / " + VideoTrimmer.fmt(playback.duration / 1000)
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                Button { text: Tr.t("Stop"); flat: true; onClicked: { playback.stop(); win.inlinePlay = ""; } }
            }
            Text { Layout.fillWidth: true; visible: VoiceRecorder.exported !== ""; text: Tr.t("Exported") + " " + VoiceRecorder.exported; color: Theme.text; elide: Text.ElideMiddle; font.family: Theme.mono; font.pixelSize: Theme.px(10) * Theme.fontScale }
            Text { Layout.fillWidth: true; visible: VoiceRecorder.exportError !== ""; text: VoiceRecorder.exportError; color: Theme.red; horizontalAlignment: Text.AlignHCenter; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Esc closes")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
            } // ColumnLayout
        } // Flickable
    }
}
