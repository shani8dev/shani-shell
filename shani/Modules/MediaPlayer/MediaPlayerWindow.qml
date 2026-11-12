// Media Player: videos and music, in a window of its own - with the music in
// ~/Music as a Library (by album, artist and song) beside what is playing. Play and pause,
// seek, the next and the one before (the folder's other files are the queue),
// volume, speed, repeat, shuffle, full screen. QtMultimedia plays (FFmpeg).
//
// Space plays and pauses; Left/Right 5 s, Shift for 30; Up/Down the volume;
// N and P the next and the one before; M mutes; F full screen; O opens a file.
// The image's default for video and audio files (dev.shani.MediaPlayer.desktop).
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import qs.Common
import qs.Services
import qs.Modules.MediaPlayer   // MusicLibraryView: a file read on first open does not see its folder by itself

AppWindow {
    id: win
    appName: "Media Player"
    doc: PlayQueue.name
    visible: PlayQueue.shown
    onGone: PlayQueue.close()
    margins: 0
    implicitWidth: 960
    implicitHeight: 620

    property bool listShown: false
    // library | playing: the music in ~/Music, or what is playing (a video always shows)
    // (PlayQueue.page: the IPC and `shani app media-player` can ask for either)
    property alias page: pageHolder.value
    QtObject { id: pageHolder; property string value: PlayQueue.page }
    onPageChanged: PlayQueue.page = page
    Connections { target: PlayQueue; function onPageChanged() { win.page = PlayQueue.page; } }
    // the song's own cover, and who it is by, from the Library when it knows the file
    readonly property var song: MusicLibrary.songs.find(x => x.path === PlayQueue.current) || null
    Connections {
        target: PlayQueue
        // a file opened from outside (a double click, `shani app`) is shown; one
        // picked in the Library leaves the Library where it is
        function onOpened() { PlayQueue.page = "playing"; }
    }
    Connections {
        target: player
        function onHasVideoChanged() { if (player.hasVideo) PlayQueue.page = "playing"; }
    }
    tools: [
        Choice { text: Tr.t("Library"); selected: win.page === "library"; onClicked: win.page = "library" },
        Choice { text: Tr.t("Now playing"); selected: win.page === "playing"; enabled: PlayQueue.current !== ""; onClicked: win.page = "playing" }
    ]
    readonly property bool audioOnly: PlayQueue.current !== "" && !player.hasVideo

    MediaPlayer {
        id: player
        source: PlayQueue.current !== "" ? "file://" + PlayQueue.current.split("/").map(encodeURIComponent).join("/") : ""
        videoOutput: video
        audioOutput: AudioOutput { volume: PlayQueue.volume; muted: PlayQueue.muted }
        playbackRate: PlayQueue.rate
        onPlaybackStateChanged: PlayQueue.playing = playbackState === MediaPlayer.PlayingState
        onPositionChanged: PlayQueue.position = position / 1000
        onDurationChanged: PlayQueue.duration = duration / 1000
        onHasVideoChanged: PlayQueue.hasVideo = hasVideo
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) PlayQueue.ended()
        onErrorOccurred: (error, text) => PlayQueue.error = text || Tr.t("This file cannot be played")
    }
    Connections {
        target: PlayQueue
        function onPlayRequested() { PlayQueue.error = ""; player.play(); }
        function onPauseRequested() { player.pause(); }
        function onToggleRequested() { win.toggle(); }
        function onSeekRequested(seconds) { player.position = Math.max(0, Math.min(player.duration, seconds * 1000)); }
    }
    // opened with a file already chosen
    Component.onCompleted: if (PlayQueue.current !== "") player.play()
    Component.onDestruction: { PlayQueue.playing = false; PlayQueue.position = 0; }

    function toggle() {
        if (player.playbackState === MediaPlayer.PlayingState)
            player.pause();
        else
            player.play();
    }
    function skip(seconds) { player.position = Math.max(0, Math.min(player.duration, player.position + seconds * 1000)); }
    function louder(by) { PlayQueue.muted = false; PlayQueue.volume = Math.max(0, Math.min(1, PlayQueue.volume + by)); }
    function pick() {
        FilePicker.open({ mode: "open", title: Tr.t("Open a video or a song"),
                          filters: PlayQueue.videoTypes.concat(PlayQueue.audioTypes),
                          startPath: PlayQueue.current !== "" ? PlayQueue.current.substring(0, PlayQueue.current.lastIndexOf("/")) : (Quickshell.env("HOME") + "/Videos"),
                          onPicked: paths => { if (paths.length) PlayQueue.open(paths[0]); } });
    }
    function key(e) {
        const big = e.modifiers & Qt.ShiftModifier;
        if (e.key === Qt.Key_Space || e.key === Qt.Key_K) win.toggle();
        else if (e.key === Qt.Key_Left) win.skip(big ? -30 : -5);
        else if (e.key === Qt.Key_Right) win.skip(big ? 30 : 5);
        else if (e.key === Qt.Key_Up) win.louder(0.05);
        else if (e.key === Qt.Key_Down) win.louder(-0.05);
        else if (e.key === Qt.Key_N) PlayQueue.next();
        else if (e.key === Qt.Key_P) PlayQueue.previous();
        else if (e.key === Qt.Key_M) PlayQueue.muted = !PlayQueue.muted;
        else if (e.key === Qt.Key_F) Niri.action("fullscreen-window");
        else if (e.key === Qt.Key_O) win.pick();
        else if (e.key === Qt.Key_L) win.listShown = !win.listShown;
        else return false;
        return true;
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => { if (win.key(e)) e.accepted = true; }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                MusicLibraryView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.page === "library"
                }
                // ---- the picture (or, for music, what is playing) ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.page === "playing"
                    color: "black"
                    VideoOutput {
                        id: video
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectFit
                        visible: player.hasVideo
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 60, 520)
                        spacing: 10
                        visible: !player.hasVideo
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !win.song || win.song.cover === ""
                            name: PlayQueue.current === "" ? "folder-videos" : "audio-x-generic"
                            size: 72
                            color: Theme.accent
                        }
                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 260
                            Layout.preferredHeight: 260
                            visible: !!win.song && win.song.cover !== ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(520, 520)
                            source: win.song && win.song.cover ? "file://" + win.song.cover.split("/").map(encodeURIComponent).join("/") : ""
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: PlayQueue.error !== "" ? PlayQueue.error : PlayQueue.current === "" ? Tr.t("Nothing playing") : win.song ? win.song.title : PlayQueue.name
                            color: PlayQueue.error !== "" ? Theme.danger : "white"
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: 16 * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: !!win.song && PlayQueue.error === ""
                            text: win.song ? win.song.artist + "  ·  " + win.song.album : ""
                            color: "#c0ffffff"
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 13 * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: PlayQueue.current === ""
                            text: Tr.t("Open a video or a song, or drop one on this window")
                            color: "#b0ffffff"
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                        }
                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            visible: PlayQueue.current === ""
                            kind: "primary"
                            text: Tr.t("Open…")
                            onClicked: win.pick()
                        }
                    }
                    // a click plays or pauses, a double click is full screen
                    MouseArea {
                        anchors.fill: parent
                        enabled: PlayQueue.current !== ""
                        onClicked: win.toggle()
                        onDoubleClicked: Niri.action("fullscreen-window")
                        onWheel: w => win.louder(w.angleDelta.y > 0 ? 0.05 : -0.05)
                    }
                    DropArea {
                        anchors.fill: parent
                        onDropped: drop => { if (drop.hasUrls && drop.urls.length) PlayQueue.open(String(drop.urls[0])); }
                    }
                }

                // ---- where it is: click or drag to seek ----
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    Layout.topMargin: 8
                    Accessible.role: Accessible.Slider
                    Accessible.name: Tr.t("Position") + ": " + PlayQueue.clock(PlayQueue.position) + " / " + PlayQueue.clock(PlayQueue.duration)
                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 5
                        radius: 3
                        color: Theme.surface3
                        Rectangle {
                            width: player.duration > 0 ? parent.width * Math.min(1, (seekArea.pressed ? seekArea.at : player.position) / player.duration) : 0
                            height: parent.height
                            radius: 3
                            color: Theme.accent
                        }
                    }
                    Rectangle {
                        visible: player.duration > 0
                        x: (player.duration > 0 ? track.width * Math.min(1, (seekArea.pressed ? seekArea.at : player.position) / player.duration) : 0) - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13; height: 13; radius: 7
                        color: Theme.accent
                    }
                    MouseArea {
                        id: seekArea
                        anchors.fill: parent
                        enabled: player.seekable && player.duration > 0
                        cursorShape: Qt.PointingHandCursor
                        property real at: 0
                        function place(x) { at = Math.max(0, Math.min(1, x / width)) * player.duration; }
                        onPressed: m => place(m.x)
                        onPositionChanged: m => place(m.x)
                        onReleased: player.position = at
                    }
                }

                // ---- the controls ----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    spacing: 4
                    IconButton { icon: "media-skip-backward"; tip: Tr.t("Previous") + " (P)"; enabled: PlayQueue.current !== ""; onClicked: PlayQueue.previous() }
                    IconButton {
                        icon: PlayQueue.playing ? "media-playback-pause" : "media-playback-start"
                        size: 40
                        on: true
                        tip: (PlayQueue.playing ? Tr.t("Pause") : Tr.t("Play")) + " (Space)"
                        enabled: PlayQueue.current !== ""
                        onClicked: win.toggle()
                    }
                    IconButton { icon: "media-skip-forward"; tip: Tr.t("Next") + " (N)"; enabled: PlayQueue.queue.length > 1; onClicked: PlayQueue.next() }
                    Text {
                        Layout.leftMargin: 8
                        text: PlayQueue.clock(seekArea.pressed ? seekArea.at / 1000 : PlayQueue.position) + " / " + PlayQueue.clock(PlayQueue.duration)
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        font.features: { "tnum": 1 }
                    }
                    Item { Layout.fillWidth: true }
                    // speed: a pick, not a number to type
                    Repeater {
                        model: [0.5, 1, 1.25, 1.5, 2]
                        Choice {
                            required property real modelData
                            text: modelData + "×"
                            selected: PlayQueue.rate === modelData
                            onClicked: PlayQueue.rate = modelData
                        }
                    }
                    IconButton { icon: "media-playlist-repeat"; tip: Tr.t("Repeat this one"); on: PlayQueue.repeatOne; onClicked: PlayQueue.repeatOne = !PlayQueue.repeatOne }
                    IconButton { icon: "media-playlist-shuffle"; tip: Tr.t("Shuffle"); on: PlayQueue.shuffle; onClicked: PlayQueue.shuffle = !PlayQueue.shuffle }
                    IconButton {
                        icon: PlayQueue.muted || PlayQueue.volume === 0 ? "audio-volume-muted" : PlayQueue.volume < 0.5 ? "audio-volume-low" : "audio-volume-high"
                        tip: (PlayQueue.muted ? Tr.t("Unmute") : Tr.t("Mute")) + " (M)"
                        onClicked: PlayQueue.muted = !PlayQueue.muted
                    }
                    Item {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 22
                        Accessible.role: Accessible.Slider
                        Accessible.name: Tr.t("Volume") + ": " + Math.round(PlayQueue.volume * 100) + " %"
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 5; radius: 3
                            color: Theme.surface3
                            Rectangle { width: parent.width * (PlayQueue.muted ? 0 : PlayQueue.volume); height: parent.height; radius: 3; color: Theme.accent }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function place(x) { PlayQueue.muted = false; PlayQueue.volume = Math.max(0, Math.min(1, x / width)); }
                            onPressed: m => place(m.x)
                            onPositionChanged: m => place(m.x)
                            onWheel: w => win.louder(w.angleDelta.y > 0 ? 0.05 : -0.05)
                        }
                    }
                    IconButton { icon: "view-list"; tip: Tr.t("Queue") + " (L)"; on: win.listShown; onClicked: win.listShown = !win.listShown }
                    IconButton { icon: "document-save-as"; tip: Tr.t("Convert…"); enabled: PlayQueue.current !== ""; onClicked: { Ui.converterFiles = [PlayQueue.current]; Ui.converter = true; } }
                    IconButton { icon: "document-open"; tip: Tr.t("Open") + " (O)"; onClicked: win.pick() }
                    IconButton { icon: "view-fullscreen"; tip: Tr.t("Full screen") + " (F)"; onClicked: Niri.action("fullscreen-window") }
                }
            }

            // ---- the queue: the folder's other files ----
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 280
                visible: win.listShown
                color: Theme.surface1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    SectionTitle { Layout.fillWidth: true; text: Tr.t("Queue") + "  ·  " + PlayQueue.queue.length }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: PlayQueue.queue
                        currentIndex: PlayQueue.index
                        delegate: Rectangle {
                            id: row
                            required property string modelData
                            required property int index
                            readonly property bool now: PlayQueue.index === index
                            width: ListView.view.width
                            height: 32
                            radius: Theme.radiusSmall
                            color: now ? Theme.accentSoft : rowArea.containsMouse ? Theme.hover : "transparent"
                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.split("/").pop()
                            Accessible.onPressAction: PlayQueue.go(index)
                            Text {
                                anchors { left: parent.left; right: parent.right; margins: 8; verticalCenter: parent.verticalCenter }
                                text: row.modelData.split("/").pop()
                                color: row.now ? Theme.text : Theme.dim
                                elide: Text.ElideMiddle
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
                            MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: PlayQueue.go(row.index) }
                        }
                    }
                }
            }
        }
    }
}
