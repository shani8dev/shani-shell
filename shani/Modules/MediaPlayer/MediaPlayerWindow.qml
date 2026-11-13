// Media Player: videos and music, in a window of its own - with the music in
// ~/Music as a Library (by album, artist and song) beside what is playing. Play and pause,
// seek, the next and the one before (the folder's other files are the queue),
// volume, speed, repeat, shuffle, full screen. QtMultimedia plays (FFmpeg).
//
// Space plays and pauses; Left/Right 5 s, Shift for 30; Up/Down the volume;
// N and P the next and the one before; M mutes; F full screen; O opens a file.
// The image's default for video and audio files (dev.shani.MediaPlayer.desktop).
import Quickshell
import Quickshell.Io
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
    onGone: { if (mini) setMini(false); PlayQueue.close(); }
    margins: 0
    // the mini player: a small floating picture, on every workspace (Niri's pinning)
    property bool mini: false
    header: !mini
    implicitWidth: mini ? 480 : 960
    implicitHeight: mini ? 270 : 620
    function myWindowId() {
        // by title: the shell names its own windows' app ids itself (Niri.own)
        const w = Object.values(Niri.windows).find(x => / — Media Player$|^Media Player$/.test(x.title || ""));
        return w ? w.id : -1;
    }
    function setMini(on) {
        if (on === mini)
            return;
        mini = on;
        if (on) { listShown = false; tracksShown = false; PlayQueue.page = "playing"; }
        const id = myWindowId();
        if (id < 0)
            return;
        if (on && !Niri.isPinned(id)) {
            Niri.togglePinned(id);                  // floats it, and carries it to each workspace
            // niri keeps a window's size whatever it asks for: niri sizes it
            Niri.action("set-window-width", "--id", id, "480");
            Niri.action("set-window-height", "--id", id, "270");
        } else if (!on && Niri.isPinned(id)) {
            Niri.togglePinned(id);
            Niri.action("move-window-to-tiling", "--id", id);
        }
    }
    onMiniChanged: PlayQueue.mini = mini
    Connections { target: PlayQueue; function onMiniRequested(on) { win.setMini(on); } }
    onCueNowChanged: PlayQueue.cue = cueNow
    Connections { target: player; function onAudioTracksChanged() { PlayQueue.audioTrackCount = player.audioTracks.length; } }
    onTagTitleChanged: PlayQueue.tagLine = [tagTitle, tagArtist].filter(x => x).join(" — ")
    onCoverChanged: PlayQueue.coverShown = cover

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

    // where it is, every few seconds while it plays, for next time
    Timer {
        interval: 5000
        repeat: true
        running: PlayQueue.playing
        onTriggered: PlayQueue.remember(PlayQueue.current, player.position / 1000, player.duration / 1000)
    }
    Timer { id: resumeNote; interval: 8000 }
    property real pendingResume: 0
    function resumeNow() {
        if (pendingResume <= 0 || !player.seekable || player.playbackState !== MediaPlayer.PlayingState || player.position <= 0)
            return;
        // taken and cleared before the seek: the seek reports a position, which calls
        // this again from inside the assignment (measured: the inner call cleared it
        // and the outer one then wrote 0 as where it was resumed from)
        const at = pendingResume;
        pendingResume = 0;
        PlayQueue.resumedFrom = at;
        PlayQueue.resumedPath = PlayQueue.current;
        resumeNote.restart();
        player.position = at * 1000;
    }

    // ---- sound and subtitle tracks; a subtitle file beside the video ----
    property bool tracksShown: false
    property string subSource: "off"             // off | embedded | file
    function trackName(md, i) {
        const title = md ? md.stringValue(MediaMetaData.Title) : "";
        const lang = md ? md.stringValue(MediaMetaData.Language) : "";
        return [title, lang].filter(x => x && x !== "C" && x !== "AnyLanguage").join(" · ") || Tr.t("Track %1", i + 1);
    }
    function setSubtitles(src, track) {
        subSource = src;
        player.activeSubtitleTrack = src === "embedded" ? track : -1;
    }
    property var cues: []                        // [{ start, end, text }] in seconds, from the file
    readonly property string cueNow: {
        if (subSource !== "file") return "";
        const t = player.position / 1000;
        const c = cues.find(x => t >= x.start && t < x.end);
        return c ? c.text : "";
    }
    function stamp(s) {
        const m = /(?:(\d+):)?(\d+):(\d+)[.,](\d+)/.exec(s);
        return m ? (Number(m[1] || 0) * 3600 + Number(m[2]) * 60 + Number(m[3]) + Number(m[4]) / 1000) : -1;
    }
    Connections {
        target: PlayQueue
        function onSubtitleFileChanged() {
            win.cues = [];
            if (PlayQueue.subtitleFile) { cueReader.command = ["cat", PlayQueue.subtitleFile]; cueReader.running = true; }
            else if (win.subSource === "file") win.setSubtitles("off", -1);
        }
        function onCurrentChanged() { if (win.subSource === "embedded") win.setSubtitles("off", -1); }
    }
    Process {
        id: cueReader
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const block of text.replace(/\r/g, "").split(/\n\s*\n/)) {
                    const lines = block.split("\n").filter(l => l.trim() !== "");
                    const i = lines.findIndex(l => l.indexOf("-->") > 0);
                    if (i < 0) continue;
                    const [a, b] = lines[i].split("-->");
                    const s = win.stamp(a), e = win.stamp(b);
                    if (s < 0 || e < 0) continue;
                    out.push({ start: s, end: e, text: lines.slice(i + 1).join("\n").replace(/<[^>]+>/g, "") });
                }
                win.cues = out;
                if (out.length) win.setSubtitles("file", -1);      // a file beside the video: shown, as players do
            }
        }
    }

    // ---- a song's own tags and cover, when the Library does not know the file ----
    readonly property string tagTitle: player.metaData.stringValue(MediaMetaData.Title)
    readonly property string tagArtist: player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist)
    readonly property string tagAlbum: player.metaData.stringValue(MediaMetaData.AlbumTitle)
    property string fileCover: ""
    Connections {
        target: PlayQueue
        function onCurrentChanged() {
            win.fileCover = "";
            if (PlayQueue.current && PlayQueue.kind(PlayQueue.current) === "audio" && !(win.song && win.song.cover)) {
                coverOut.command = ["sh", "-c", 'd=${XDG_CACHE_HOME:-$HOME/.cache}/shani-shell/covers; mkdir -p "$d"; o="$d/$(printf %s "$1" | md5sum | cut -c1-16).jpg"; [ -s "$o" ] || ffmpeg -loglevel error -y -i "$1" -an -map 0:v:0 -frames:v 1 "$o" 2>/dev/null; [ -s "$o" ] && printf %s "$o"', "sh", PlayQueue.current];
                coverOut.running = true;
            }
        }
    }
    Process { id: coverOut; stdout: StdioCollector { onStreamFinished: win.fileCover = text.trim() } }
    readonly property string cover: win.song && win.song.cover ? win.song.cover : fileCover

    MediaPlayer {
        id: player
        source: PlayQueue.current !== "" ? "file://" + PlayQueue.current.split("/").map(encodeURIComponent).join("/") : ""
        videoOutput: video
        audioOutput: AudioOutput { volume: PlayQueue.volume; muted: PlayQueue.muted }
        playbackRate: PlayQueue.rate
        onPlaybackStateChanged: PlayQueue.playing = playbackState === MediaPlayer.PlayingState
        onPositionChanged: { PlayQueue.position = player.position / 1000; win.resumeNow(); }
        onDurationChanged: {
            PlayQueue.duration = player.duration / 1000;
            // where it was left last time (PlayQueue.resumeAt), once its length is known
            const r = PlayQueue.resumePoint(PlayQueue.current);
            if (player.duration > 0 && r > 0 && player.position < 2000 && PlayQueue.resumedFrom === 0)
                win.pendingResume = r;
            win.resumeNow();
        }
        // a seek before playback has really started is dropped (measured twice: the
        // note said 1:03, the clock 0:01; then seekable alone was not enough) - so it
        // waits for the first position the playing file reports
        onSeekableChanged: win.resumeNow()
        onHasVideoChanged: PlayQueue.hasVideo = hasVideo
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) { PlayQueue.forget(PlayQueue.current); PlayQueue.ended(); }
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
        else if (e.key === Qt.Key_I) win.setMini(!win.mini);
        else if (e.key === Qt.Key_Escape && win.mini) win.setMini(false);
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
                    visible: win.page === "library" && !win.mini
                }
                // ---- the picture (or, for music, what is playing) ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.page === "playing" || win.mini
                    color: "black"
                    // the mini player's own controls, over the picture while the pointer is on it
                    HoverHandler { id: miniHover; enabled: win.mini }
                    MouseArea {
                        anchors.fill: parent
                        visible: win.mini
                        z: 2
                        acceptedButtons: Qt.LeftButton
                        onPressed: win.startSystemMove()        // no header: the picture moves it
                        onDoubleClicked: win.setMini(false)
                    }
                    RowLayout {
                        z: 3
                        anchors.centerIn: parent
                        visible: win.mini && miniHover.hovered
                        spacing: 14
                        IconButton { size: 40; icon: "media-skip-backward"; tip: Tr.t("Previous"); onClicked: PlayQueue.previous() }
                        IconButton { size: 52; on: true; icon: PlayQueue.playing ? "media-playback-pause" : "media-playback-start"; tip: Tr.t("Play or pause"); onClicked: win.toggle() }
                        IconButton { size: 40; icon: "media-skip-forward"; tip: Tr.t("Next"); onClicked: PlayQueue.next() }
                    }
                    IconButton {
                        z: 3
                        anchors { top: parent.top; right: parent.right; margins: 8 }
                        visible: win.mini && miniHover.hovered
                        icon: "view-restore"
                        tip: Tr.t("Back to the full player") + " (I)"
                        onClicked: win.setMini(false)
                    }
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
                            visible: win.cover === ""
                            name: PlayQueue.current === "" ? "folder-videos" : "audio-x-generic"
                            size: 72
                            color: Theme.accent
                        }
                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 260
                            Layout.preferredHeight: 260
                            visible: win.cover !== ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(520, 520)
                            source: win.cover ? "file://" + win.cover.split("/").map(encodeURIComponent).join("/") : ""
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: PlayQueue.error !== "" ? PlayQueue.error : PlayQueue.current === "" ? Tr.t("Nothing playing") : win.song ? win.song.title : (win.tagTitle || PlayQueue.name)
                            color: PlayQueue.error !== "" ? Theme.danger : "white"
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: 16 * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: (!!win.song || win.tagArtist !== "" || win.tagAlbum !== "") && PlayQueue.error === ""
                            text: win.song ? win.song.artist + "  ·  " + win.song.album : [win.tagArtist, win.tagAlbum].filter(x => x).join("  ·  ")
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
                        z: -1
                        anchors.fill: parent
                        enabled: PlayQueue.current !== ""
                        onClicked: win.toggle()
                        onDoubleClicked: Niri.action("fullscreen-window")
                        onWheel: w => win.louder(w.angleDelta.y > 0 ? 0.05 : -0.05)
                    }
                    DropArea {
                        z: -1
                        anchors.fill: parent
                        onDropped: drop => { if (drop.hasUrls && drop.urls.length) PlayQueue.open(String(drop.urls[0])); }
                    }
                    // the subtitle file's line, outlined so it reads on any picture
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: parent.height * 0.07
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.86
                        visible: win.cueNow !== ""
                        text: win.cueNow
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: "white"
                        style: Text.Outline
                        styleColor: "black"
                        font.family: Theme.font
                        font.pixelSize: Math.max(18, parent.height * 0.045)
                        font.weight: Font.DemiBold
                    }
                    // "Resumed at 12:34" for a few seconds, with the way back to the start
                    Rectangle {
                        anchors { top: parent.top; left: parent.left; margins: 14 }
                        visible: resumeNote.running && PlayQueue.resumedFrom > 0
                        implicitWidth: resumeRow.implicitWidth + 20
                        implicitHeight: 36
                        radius: 18
                        color: Qt.rgba(0, 0, 0, 0.66)
                        RowLayout {
                            id: resumeRow
                            anchors.centerIn: parent
                            spacing: 10
                            Text { text: Tr.t("Resumed at %1", PlayQueue.clock(PlayQueue.resumedFrom)); color: "white"; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                            Button { text: Tr.t("Start over"); flat: true; onClicked: { player.position = 0; PlayQueue.resumedFrom = 0; resumeNote.stop(); } }
                        }
                    }
                    // sound and subtitle tracks
                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
                        visible: win.tracksShown
                        width: 300
                        implicitHeight: tracksCol.implicitHeight + 24
                        radius: Theme.radiusSmall
                        color: Theme.alpha(Theme.bg, 0.94)
                        border.width: 1
                        border.color: Theme.border
                        MouseArea { anchors.fill: parent }
                        ColumnLayout {
                            id: tracksCol
                            x: 12; y: 12
                            width: parent.width - 24
                            spacing: 6
                            SectionTitle { Layout.fillWidth: true; text: Tr.t("Sound") }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: player.audioTracks
                                    Choice {
                                        required property var modelData
                                        required property int index
                                        text: win.trackName(modelData, index)
                                        selected: player.activeAudioTrack === index || (player.activeAudioTrack < 0 && index === 0)
                                        onClicked: player.activeAudioTrack = index
                                    }
                                }
                            }
                            SectionTitle { Layout.fillWidth: true; text: Tr.t("Subtitles") }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Choice { text: Tr.t("Off"); selected: win.subSource === "off"; onClicked: win.setSubtitles("off", -1) }
                                Repeater {
                                    model: player.subtitleTracks
                                    Choice {
                                        required property var modelData
                                        required property int index
                                        text: win.trackName(modelData, index)
                                        selected: win.subSource === "embedded" && player.activeSubtitleTrack === index
                                        onClicked: win.setSubtitles("embedded", index)
                                    }
                                }
                                Choice {
                                    visible: win.cues.length > 0
                                    text: PlayQueue.subtitleFile.split("/").pop()
                                    selected: win.subSource === "file"
                                    onClicked: win.setSubtitles("file", -1)
                                }
                            }
                        }
                    }
                }

                // ---- where it is: click or drag to seek ----
                Item {
                    visible: !win.mini
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
                    visible: !win.mini
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
                    IconButton {
                        icon: "media-view-subtitles"
                        tip: Tr.t("Sound and subtitles")
                        visible: player.audioTracks.length > 1 || player.subtitleTracks.length > 0 || win.cues.length > 0
                        on: win.tracksShown
                        onClicked: win.tracksShown = !win.tracksShown
                    }
                    IconButton { icon: "view-list"; tip: Tr.t("Queue") + " (L)"; on: win.listShown; onClicked: win.listShown = !win.listShown }
                    IconButton { icon: "document-save-as"; tip: Tr.t("Convert…"); enabled: PlayQueue.current !== ""; onClicked: { Ui.converterFiles = [PlayQueue.current]; Ui.converter = true; } }
                    IconButton { icon: "document-open"; tip: Tr.t("Open") + " (O)"; onClicked: win.pick() }
                    IconButton { icon: "view-restore"; tip: Tr.t("Mini player") + " (I)"; enabled: PlayQueue.current !== ""; onClicked: win.setMini(true) }
                    IconButton { icon: "view-fullscreen"; tip: Tr.t("Full screen") + " (F)"; onClicked: Niri.action("fullscreen-window") }
                }
            }

            // ---- the queue: the folder's other files ----
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 280
                visible: win.listShown && !win.mini
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
