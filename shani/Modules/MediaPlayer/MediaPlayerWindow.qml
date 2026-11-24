// Media Player: videos and music, in a window of its own - with the music in
// ~/Music as a Library (by album, artist and song) beside what is playing. Play and pause,
// seek, the next and the one before (the folder's other files are the queue),
// volume, speed, repeat, shuffle, full screen. QtMultimedia plays (FFmpeg).
//
// Space plays and pauses; Left/Right 5 s, Shift for 30; Up/Down the volume;
// N and P the next and the one before, . and , the next and previous chapter;
// M mutes; S shuffles, Shift+R cycles repeat; F full screen; O opens a file;
// R Radio, T Live TV, L the queue, I the mini player.
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
        // an explicit Radio/Live TV choice wins over an auto-switch: a video
        // still loaded from an earlier file must not hijack the chosen page
        function onOpened() { if (PlayQueue.page !== "radio" && PlayQueue.page !== "live") PlayQueue.page = "playing"; }
    }
    Connections {
        target: player
        function onHasVideoChanged() { if (player.hasVideo && PlayQueue.page !== "radio" && PlayQueue.page !== "live") PlayQueue.page = "playing"; }
    }
    tools: [
        Choice { text: Tr.t("Library"); selected: win.page === "library"; onClicked: win.page = "library" },
        Choice { text: Tr.t("Radio"); selected: win.page === "radio"; onClicked: { win.page = "radio"; if (Radio.showing === "") Radio.show(Radio.favourites.length ? "favourites" : "featured"); } },
        Choice { text: Tr.t("Live TV"); selected: win.page === "live"; onClicked: { win.page = "live"; if (LiveTv.channels.length === 0) { if (LiveTv.source) LiveTv.load(LiveTv.source); else LiveTv.loadDefaults(); } } },
        Choice { text: Tr.t("Now playing"); selected: win.page === "playing"; enabled: PlayQueue.current !== ""; onClicked: win.page = "playing" }
    ]

    // where it is, every few seconds while it plays, for next time
    Timer {
        interval: 5000
        repeat: true
        running: PlayQueue.playing
        onTriggered: PlayQueue.remember(PlayQueue.current, player.position / 1000, player.duration / 1000)
    }
    Timer { id: resumeNote; interval: 8000 }
    Timer { id: frameSavedNote; interval: 3000 }
    // a video has no now-playing page of its own: the title rides over the picture
    Timer { id: titleNote; interval: 4000 }
    Connections { target: PlayQueue; function onCurrentChanged() { titleNote.restart(); } }
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
    // a subtitle file can be a moment out - a broadcast rip, a fan-made .srt.
    // The whole track moves, by the step the buttons use, so it lines up
    // without touching the file (which may be read-only, or shared).
    property real subShift: PlayQueue.subtitleShift   // seconds added to every cue
    readonly property var subShifts: [-5, -1, -0.5, 0, 0.5, 1, 5]
    function nudgeSubtitles(dir) {
        // the step buttons walk a short ladder, so one press is a small move
        // and a held one keeps going
        const steps = win.subShifts;
        let best = 0;
        for (const s of steps)
            if (Math.abs(s - win.subShift) < Math.abs(best - win.subShift)) best = s;
        const at = steps.indexOf(best);
        const next = Math.max(0, Math.min(steps.length - 1, at + dir));
        win.subShift = steps[next];
        PlayQueue.setSubtitleShift(win.subShift);
    }
    readonly property string cueNow: {
        if (subSource !== "file") return "";
        const t = player.position / 1000 - win.subShift;
        const c = cues.find(x => t >= x.start && t < x.end);
        return c ? c.text : "";
    }
    // the chapter the playhead is in (or the last one before it): its row is lit
    function chapterNow(c) {
        const t = player.position / 1000;
        let at = -1;
        for (let i = 0; i < PlayQueue.chapters.length; i++) {
            if (t >= PlayQueue.chapters[i].start) at = i;
            else break;
        }
        return at >= 0 && PlayQueue.chapters[at] === c;
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

    // Showtime's "Take screenshot": the frame on screen, full size, into
    // ~/Pictures/Screenshots as "<video> <h-mm-ss>.png" (ffmpeg seeks there and keeps one frame)
    property string frameSaved: ""
    function saveFrame() {
        if (!player.hasVideo || PlayQueue.current === "") return;
        const s = Math.max(0, player.position / 1000);
        const stamp = Math.floor(s / 3600) + "-" + String(Math.floor(s % 3600 / 60)).padStart(2, "0") + "-" + String(Math.floor(s % 60)).padStart(2, "0");
        const name = PlayQueue.current.split("/").pop().replace(/\.[^.]+$/, "");
        frameProc.command = ["sh", "-c", 'd="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$d"; o="$d/$2 $3.png"; i=2
            while [ -e "$o" ]; do o="$d/$2 $3 ($i).png"; i=$((i+1)); done
            ffmpeg -nostdin -loglevel error -ss "$4" -i "$1" -frames:v 1 "$o" && printf %s "$o"', "sh", PlayQueue.current, name, stamp, s.toFixed(3)];
        frameProc.running = true;
    }
    Process {
        id: frameProc
        stdout: StdioCollector { onStreamFinished: { win.frameSaved = text.trim(); Ui.mediaFrameSaved = win.frameSaved; frameSavedNote.restart(); } }
    }

    MediaPlayer {
        id: player
        source: PlayQueue.current === "" ? "" : PlayQueue.isStream ? PlayQueue.current
                : "file://" + PlayQueue.current.split("/").map(encodeURIComponent).join("/")
        videoOutput: video
        audioOutput: AudioOutput { volume: PlayQueue.volume; muted: PlayQueue.muted }
        playbackRate: PlayQueue.rate
        onPlaybackStateChanged: PlayQueue.playing = playbackState === MediaPlayer.PlayingState
        onPositionChanged: {
            PlayQueue.position = player.position / 1000;
            win.resumeNow();
            const jump = PlayQueue.loopJump(PlayQueue.position);
            if (jump >= 0) player.position = jump * 1000;
        }
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
        function onFrameRequested() { win.saveFrame(); }
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
    // one function for the toolbar and Shift+R, so they cannot drift apart
    function cycleRepeat() { PlayQueue.repeat = PlayQueue.repeat === "off" ? "all" : PlayQueue.repeat === "all" ? "one" : "off"; }
    // chapters are click-only in the tracks card; . and , step through them too
    function stepChapter(dir) {
        const cs = PlayQueue.chapters;
        if (!cs || cs.length === 0 || player.duration <= 0)
            return false;
        const t = player.position / 1000;
        let at = 0;
        for (let i = 0; i < cs.length; i++) {
            if (cs[i].start <= t) at = i;
            else break;
        }
        player.position = cs[Math.max(0, Math.min(cs.length - 1, at + dir))].start * 1000;
        return true;
    }
    // go to a typed time: "mm:ss" or "hh:mm:ss"; rejects anything else
    function goToTime(s) {
        const parts = String(s || "").trim().split(":");
        if (parts.length < 1 || parts.length > 3 || parts.some(p => !/^\d+$/.test(p)))
            return false;
        const sec = parts.reduce((acc, p) => acc * 60 + parseInt(p, 10), 0);
        if (!isFinite(sec) || sec < 0)
            return false;
        player.position = Math.min(player.duration, sec * 1000);
        return true;
    }
    function playStreamUrl(u) {
        const url = String(u || "").trim();
        if (/^https?:\/\//.test(url)) { PlayQueue.playStream(url); win.streamShown = false; return true; }
        return false;
    }
    property bool streamShown: false
    property bool recentShown: false
    property bool infoShown: false
    property bool goError: false
    property bool streamError: false
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
        else if (e.key === Qt.Key_Comma) win.stepChapter(-1);
        else if (e.key === Qt.Key_Period) win.stepChapter(1);
        else if (e.key === Qt.Key_S) PlayQueue.shuffle = !PlayQueue.shuffle;
        else if (e.key === Qt.Key_M) PlayQueue.muted = !PlayQueue.muted;
        else if (e.key === Qt.Key_F) Niri.action("fullscreen-window");
        else if (e.key === Qt.Key_O) win.pick();
        else if (e.key === Qt.Key_L) win.listShown = !win.listShown;
        else if (e.key === Qt.Key_R && big) win.cycleRepeat();
        else if (e.key === Qt.Key_R) { win.page = "radio"; if (Radio.showing === "") Radio.show(Radio.favourites.length ? "favourites" : "featured"); }
        else if (e.key === Qt.Key_T) { win.page = "live"; if (!LiveTv.channels.length) { if (LiveTv.source) LiveTv.load(LiveTv.source); else LiveTv.loadDefaults(); } }
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
                RadioView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.page === "radio" && !win.mini
                }
                LiveTvView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.page === "live" && !win.mini
                }
                // ---- the picture (or, for music, what is playing) ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.page === "playing" || win.mini
                    color: "black"
                    // the mini player's own controls, over the picture while the pointer is on it
                    HoverHandler { id: miniHover; enabled: win.mini }
                    HoverHandler { id: videoHover; enabled: !win.mini }
                    MouseArea {
                        objectName: "nav:pointer"          // the mini player moved by its picture (Mod+arrows move it with keys)
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
                        spacing: Theme.px(14)
                        IconButton { size: Theme.px(40); icon: "media-skip-backward"; tip: Tr.t("Previous"); onClicked: PlayQueue.previous() }
                        IconButton { size: Theme.px(52); on: true; icon: PlayQueue.playing ? "media-playback-pause" : "media-playback-start"; tip: Tr.t("Play or pause"); onClicked: win.toggle() }
                        IconButton { size: Theme.px(40); icon: "media-skip-forward"; tip: Tr.t("Next"); onClicked: PlayQueue.next() }
                        IconButton { size: Theme.px(40); visible: player.hasVideo; icon: "camera-photo"; tip: Tr.t("Save this frame as a picture"); onClicked: win.saveFrame() }
                    }
                    IconButton {
                        z: 3
                        anchors { top: parent.top; right: parent.right; margins: Theme.px(8) }
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
                        spacing: Theme.px(10)
                        visible: !player.hasVideo
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            visible: win.cover === ""
                            name: PlayQueue.current === "" ? "folder-videos" : "audio-x-generic"
                            size: Theme.px(72)
                            color: Theme.accent
                        }
                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Theme.px(260)
                            Layout.preferredHeight: Theme.px(260)
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
                            font.pixelSize: Theme.px(16) * Theme.fontScale
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
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: MediaInfo.line !== ""
                            text: MediaInfo.line
                            color: "#a0ffffff"
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                            // the one-line header opens the whole answer
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.infoShown = !win.infoShown
                                Accessible.role: Accessible.Button
                                Accessible.name: Tr.t("Media properties")
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: PlayQueue.current === ""
                            text: Tr.t("Open a video or a song, or drop one on this window")
                            color: "#b0ffffff"
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: Theme.px(12) * Theme.fontScale
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
                        objectName: "nav:keys"          // Space / K and the Play button; F full screen
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
                    // the title fades in when a video starts, and returns on hover
                    Rectangle {
                        z: 4
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.px(14) }
                        visible: player.hasVideo && !win.mini && (titleNote.running || videoHover.hovered)
                        implicitHeight: videoTitle.implicitHeight + Theme.px(16)
                        radius: Theme.radiusSmall
                        color: Qt.rgba(0, 0, 0, 0.6)
                        Text {
                            id: videoTitle
                            anchors { fill: parent; margins: Theme.px(8) }
                            text: win.song ? win.song.title : (win.tagTitle || PlayQueue.name)
                            color: "white"
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(15) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                    }
                    // "Resumed at 12:34" for a few seconds, with the way back to the start
                    Rectangle {
                        anchors { top: parent.top; left: parent.left; margins: Theme.px(14) }
                        visible: resumeNote.running && PlayQueue.resumedFrom > 0
                        implicitWidth: resumeRow.implicitWidth + 20
                        implicitHeight: Theme.px(36)
                        radius: Theme.px(18)
                        color: Qt.rgba(0, 0, 0, 0.66)
                        RowLayout {
                            id: resumeRow
                            anchors.centerIn: parent
                            spacing: Theme.px(10)
                            Text { text: Tr.t("Resumed at %1", PlayQueue.clock(PlayQueue.resumedFrom)); color: "white"; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                            Button { text: Tr.t("Start over"); flat: true; onClicked: { player.position = 0; PlayQueue.resumedFrom = 0; resumeNote.stop(); } }
                        }
                    }
                    // "Saved picture.png" for a few seconds. Sized from the window,
                    // not from its own child: a size that reads a child's implicit
                    // size stalled the whole window's creation.
                    Rectangle {
                        anchors { top: parent.top; left: parent.left; margins: Theme.px(14) }
                        visible: frameSavedNote.running && win.frameSaved !== ""
                        width: Math.min(parent.width - Theme.px(40), Theme.px(320))
                        height: Theme.px(40)
                        radius: Theme.px(20)
                        color: Qt.rgba(0, 0, 0, 0.66)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(10)
                            spacing: Theme.px(10)
                            Text { Layout.fillWidth: true; text: Tr.t("Saved %1", win.frameSaved); color: "white"; elide: Text.ElideMiddle; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                            Text { text: Tr.t("Open"); color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                        }
                        // the whole toast opens it: a Button with this handler here
                        // stopped the window from ever mapping
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Qt.openUrlExternally(win.frameSaved); frameSavedNote.stop(); }
                            Accessible.role: Accessible.Button
                            Accessible.name: Tr.t("Open the saved picture")
                            Accessible.onPressAction: { Qt.openUrlExternally(win.frameSaved); frameSavedNote.stop(); }
                        }
                    }
                    // sound and subtitle tracks
                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom; margins: Theme.px(12) }
                        visible: win.tracksShown
                        width: Theme.px(300)
                        implicitHeight: tracksCol.implicitHeight + 24
                        radius: Theme.radiusSmall
                        color: Theme.alpha(Theme.bg, 0.94)
                        border.width: 1
                        border.color: Theme.border
                        MouseArea { anchors.fill: parent; objectName: "nav:pointer" }   // swallows clicks on the card
                        ColumnLayout {
                            id: tracksCol
                            x: 12; y: 12
                            width: parent.width - 24
                            spacing: Theme.px(6)
                            SectionTitle { Layout.fillWidth: true; text: Tr.t("Sound") }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.px(6)
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
                                spacing: Theme.px(6)
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
                            // a downloaded subtitle need not sit beside the video
                            Button {
                                Layout.fillWidth: true
                                text: Tr.t("Open subtitle…")
                                flat: true
                                onClicked: FilePicker.open({ mode: "open", title: Tr.t("A subtitle file"),
                                    filters: ["srt", "vtt"],
                                    onPicked: paths => { if (paths.length) PlayQueue.subtitleFile = paths[0]; } })
                            }
                            // a subtitle track that is a moment out: move it whole
                            RowLayout {
                                Layout.fillWidth: true
                                visible: win.cues.length > 0 && win.subSource === "file"
                                spacing: Theme.px(6)
                                Text { text: Tr.t("Timing"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                                IconButton { icon: "media-seek-backward"; tip: Tr.t("Earlier"); size: Theme.px(24); onClicked: win.nudgeSubtitles(-1) }
                                Text {
                                    text: (PlayQueue.subtitleShift > 0 ? "+" : "") + PlayQueue.subtitleShift.toFixed(1) + " s"
                                    color: Theme.text
                                    font.family: Theme.mono
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
                                IconButton { icon: "media-seek-forward"; tip: Tr.t("Later"); size: Theme.px(24); onClicked: win.nudgeSubtitles(1) }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: Tr.t("Reset")
                                    flat: true
                                    enabled: PlayQueue.subtitleShift !== 0
                                    onClicked: { PlayQueue.setSubtitleShift(0); win.subShift = 0; }
                                }
                            }
                            // chapters, read from the file by ffprobe: pick one to jump to
                            SectionTitle { Layout.fillWidth: true; visible: PlayQueue.chapters.length > 0; text: Tr.t("Chapters") }
                            ListView {
                                id: chapterList
                                Layout.fillWidth: true
                                visible: PlayQueue.chapters.length > 0
                                implicitHeight: Math.min(180, PlayQueue.chapters.length * 30)
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: PlayQueue.chapters
                                delegate: Rectangle {
                                    id: chapterRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool now: chapterNow(chapterRow.modelData)
                                    width: chapterList.width
                                    height: Theme.px(28)
                                    radius: Theme.radiusSmall
                                    color: chapterRow.now ? Theme.accentSoft : chapterArea.containsMouse ? Theme.hover : "transparent"
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: Theme.px(8); rightMargin: Theme.px(8) }
                                        spacing: Theme.px(8)
                                        Text {
                                            text: PlayQueue.clock(chapterRow.modelData.start)
                                            color: chapterRow.now ? Theme.accent : Theme.dim
                                            font.family: Theme.mono
                                            font.pixelSize: Theme.px(11) * Theme.fontScale
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: chapterRow.modelData.title || Tr.t("Chapter %1", chapterRow.index + 1)
                                            color: Theme.text
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.px(12) * Theme.fontScale
                                        }
                                    }
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: (chapterRow.modelData.title || Tr.t("Chapter %1", chapterRow.index + 1)) + ", " + PlayQueue.clock(chapterRow.modelData.start)
                                    Accessible.onPressAction: player.position = chapterRow.modelData.start * 1000
                                    MouseArea { id: chapterArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: player.position = chapterRow.modelData.start * 1000 }
                                    KeyFocus { onActivated: player.position = chapterRow.modelData.start * 1000 }
                                }
                            }
                        }
                    }
                    // ---- open a network stream (http/https) ----
                    Rectangle {
                        anchors { top: parent.top; right: parent.right; margins: Theme.px(12) }
                        visible: win.streamShown
                        width: Theme.px(320)
                        implicitHeight: streamCol.implicitHeight + 24
                        radius: Theme.radiusSmall
                        color: Theme.alpha(Theme.bg, 0.96)
                        border.width: 1
                        border.color: Theme.border
                        MouseArea { anchors.fill: parent; objectName: "nav:pointer" }
                        ColumnLayout {
                            id: streamCol
                            x: 12; y: 12
                            width: parent.width - 24
                            spacing: Theme.px(6)
                            SectionTitle { Layout.fillWidth: true; text: Tr.t("Network stream") }
                            TextField {
                                id: streamField
                                Layout.fillWidth: true
                                placeholder: "https://…"
                                label: Tr.t("Stream address")
                                onAccepted: { win.streamError = !win.playStreamUrl(text); }
                            }
                            Text { visible: win.streamError; text: Tr.t("Enter an http(s) address"); color: Theme.red; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                Button { text: Tr.t("Play stream"); kind: "primary"; onClicked: { win.streamError = !win.playStreamUrl(streamField.text); } }
                            }
                        }
                    }

                    // ---- recent media: files with a saved resume point ----
                    Rectangle {
                        anchors { top: parent.top; right: parent.right; margins: Theme.px(12) }
                        visible: win.recentShown
                        width: Theme.px(320)
                        implicitHeight: Math.min(360, recentCol.implicitHeight + 24)
                        radius: Theme.radiusSmall
                        color: Theme.alpha(Theme.bg, 0.96)
                        border.width: 1
                        border.color: Theme.border
                        MouseArea { anchors.fill: parent; objectName: "nav:pointer" }
                        ColumnLayout {
                            id: recentCol
                            x: 12; y: 12
                            width: parent.width - 24
                            spacing: Theme.px(6)
                            SectionTitle { Layout.fillWidth: true; text: Tr.t("Recent media") }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: PlayQueue.recent
                                delegate: Rectangle {
                                    required property string modelData
                                    width: ListView.view.width
                                    height: Theme.px(34)
                                    radius: Theme.radiusSmall
                                    color: recentArea.containsMouse ? Theme.hover : "transparent"
                                    Text {
                                        anchors { left: parent.left; right: parent.right; margins: Theme.px(8); verticalCenter: parent.verticalCenter }
                                        text: modelData.split("/").pop() + "  ·  " + PlayQueue.clock(PlayQueue.resumePoint(modelData))
                                        color: Theme.text
                                        elide: Text.ElideMiddle
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                    MouseArea {
                                        id: recentArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { PlayQueue.playRecent(modelData); win.recentShown = false; }
                                    }
                                }
                            }
                            Text { visible: PlayQueue.recent.length === 0; text: Tr.t("Nothing watched yet"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        }
                    }

                    // ---- media properties: the probe MediaInfo already did, expanded ----
                    Rectangle {
                        objectName: "media:properties"
                        anchors { left: parent.left; bottom: parent.bottom; margins: Theme.px(12) }
                        visible: win.infoShown && !win.mini
                        width: Theme.px(320)
                        implicitHeight: Math.min(infoCol.implicitHeight + 24, parent.height - 100)
                        radius: Theme.radiusSmall
                        color: Theme.alpha(Theme.bg, 0.96)
                        border.width: 1
                        border.color: Theme.border
                        MouseArea { anchors.fill: parent; objectName: "nav:pointer" }   // swallows clicks on the card
                        ColumnLayout {
                            id: infoCol
                            x: 12; y: 12
                            width: parent.width - 24
                            spacing: Theme.px(6)
                            RowLayout {
                                Layout.fillWidth: true
                                SectionTitle { Layout.fillWidth: true; text: Tr.t("Media properties") }
                                IconButton { icon: "window-close"; size: Theme.px(24); tip: Tr.t("Close"); onClicked: win.infoShown = false }
                            }
                            Repeater {
                                model: MediaInfo.details
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Theme.px(8)
                                    Text {
                                        Layout.preferredWidth: Theme.px(96)
                                        text: modelData.label
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        color: Theme.text
                                        wrapMode: Text.WrapAnywhere
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                }
                            }
                            EmptyState {
                                Layout.fillWidth: true
                                visible: MediaInfo.details.length === 0
                                icon: "document-properties"
                                title: MediaInfo.loading ? Tr.t("Reading media properties…")
                                    : !MediaInfo.available ? Tr.t("MediaInfo is not installed")
                                    : PlayQueue.current === "" ? Tr.t("Nothing playing")
                                    : Tr.t("No media properties")
                                subtitle: !MediaInfo.available && !MediaInfo.loading ? Tr.t("Install mediainfo to see what a file is made of") : ""
                            }
                        }
                    }
                }

                // ---- where it is: click or drag to seek ----
                Item {
                    visible: !win.mini
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(22)
                    Layout.leftMargin: Theme.px(14)
                    Layout.rightMargin: Theme.px(14)
                    Layout.topMargin: Theme.px(8)
                    Accessible.role: Accessible.Slider
                    Accessible.name: Tr.t("Position") + ": " + PlayQueue.clock(PlayQueue.position) + " / " + PlayQueue.clock(PlayQueue.duration)
                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: Theme.px(5)
                        radius: Theme.px(3)
                        color: Theme.surface3
                        Rectangle {
                            width: player.duration > 0 ? parent.width * Math.min(1, (seekArea.pressed ? seekArea.at : player.position) / player.duration) : 0
                            height: parent.height
                            radius: Theme.px(3)
                            color: Theme.accent
                        }
                    }
                    Rectangle {
                        visible: player.duration > 0
                        x: (player.duration > 0 ? track.width * Math.min(1, (seekArea.pressed ? seekArea.at : player.position) / player.duration) : 0) - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.px(13); height: Theme.px(13); radius: Theme.px(7)
                        color: Theme.accent
                    }
                    // chapter marks on the timeline: the list lives in the tracks card,
                    // but the bar itself should show where the breaks are
                    Repeater {
                        model: player.duration > 0 ? PlayQueue.chapters : []
                        Rectangle {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            x: track.width * Math.max(0, Math.min(1, modelData.start / player.duration)) - width / 2
                            width: Theme.px(2); height: Theme.px(11); radius: Theme.px(1)
                            color: Qt.rgba(1, 1, 1, 0.55)
                        }
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
                    // keys and a controller: Left / Right 10 s back / on
                    KeyFocus { enabled: seekArea.enabled; slider: true; onStep: dir => player.position = Math.max(0, Math.min(player.duration, player.position + dir * 10000)) }
                }

                // ---- the controls ----
                RowLayout {
                    visible: !win.mini
                    Layout.fillWidth: true
                    Layout.margins: Theme.px(10)
                    spacing: Theme.px(4)
                    IconButton { icon: "media-skip-backward"; tip: Tr.t("Previous") + " (P)"; enabled: PlayQueue.current !== ""; onClicked: PlayQueue.previous() }
                    IconButton {
                        icon: PlayQueue.playing ? "media-playback-pause" : "media-playback-start"
                        size: Theme.px(40)
                        on: true
                        tip: (PlayQueue.playing ? Tr.t("Pause") : Tr.t("Play")) + " (Space)"
                        enabled: PlayQueue.current !== ""
                        onClicked: win.toggle()
                    }
                    IconButton { icon: "media-skip-forward"; tip: Tr.t("Next") + " (N)"; enabled: PlayQueue.queue.length > 1; onClicked: PlayQueue.next() }
                    IconButton { icon: "media-playback-stop"; tip: Tr.t("Stop"); enabled: PlayQueue.current !== ""; onClicked: PlayQueue.stop() }
                    Text {
                        Layout.leftMargin: Theme.px(8)
                        text: PlayQueue.clock(seekArea.pressed ? seekArea.at / 1000 : PlayQueue.position) + " / " + PlayQueue.clock(PlayQueue.duration)
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                        font.features: { "tnum": 1 }
                    }
                    TextField {
                        id: goField
                        Layout.preferredWidth: Theme.px(90)
                        placeholder: "mm:ss"
                        label: Tr.t("Go to time")
                        input.font.features: { "tnum": 1 }
                        onAccepted: if (!win.goToTime(text)) win.goError = true; else win.goError = false
                    }
                    Button { text: Tr.t("Go"); flat: true; enabled: PlayQueue.current !== ""; onClicked: { if (!win.goToTime(goField.text)) win.goError = true; else win.goError = false; } }
                    Text { visible: win.goError; text: Tr.t("Bad time"); color: Theme.red; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale }
                    Item { Layout.fillWidth: true }
                    Button { text: "A"; flat: true; checked: PlayQueue.loopA >= 0; onClicked: PlayQueue.setLoopA(PlayQueue.position); Accessible.name: Tr.t("Set loop start") }
                    Button { text: "B"; flat: true; checked: PlayQueue.loopB > PlayQueue.loopA; onClicked: PlayQueue.setLoopB(PlayQueue.position); Accessible.name: Tr.t("Set loop end") }
                    Button { text: Tr.t("Loop off"); flat: true; visible: PlayQueue.loopActive; onClicked: PlayQueue.clearLoop() }
                    // speed: a pick, not a number to type
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Speed")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Repeater {
                        model: [0.5, 1, 1.25, 1.5, 2]
                        Choice {
                            required property real modelData
                            text: modelData + "×"
                            selected: PlayQueue.rate === modelData
                            onClicked: PlayQueue.rate = modelData
                        }
                    }
                    IconButton {
                        icon: PlayQueue.repeat === "one" ? "media-playlist-repeat-song" : "media-playlist-repeat"
                        tip: (PlayQueue.repeat === "off" ? Tr.t("Repeat off") : PlayQueue.repeat === "all" ? Tr.t("Repeat all") : Tr.t("Repeat this one")) + " (Shift+R)"
                        on: PlayQueue.repeat !== "off"
                        onClicked: win.cycleRepeat()
                    }
                    IconButton { icon: "media-playlist-shuffle"; tip: Tr.t("Shuffle") + " (S)"; on: PlayQueue.shuffle; onClicked: PlayQueue.shuffle = !PlayQueue.shuffle }
                    IconButton {
                        icon: PlayQueue.muted || PlayQueue.volume === 0 ? "audio-volume-muted" : PlayQueue.volume < 0.5 ? "audio-volume-low" : "audio-volume-high"
                        tip: (PlayQueue.muted ? Tr.t("Unmute") : Tr.t("Mute")) + " (M)"
                        onClicked: PlayQueue.muted = !PlayQueue.muted
                    }
                    Item {
                        Layout.preferredWidth: Theme.px(90)
                        Layout.preferredHeight: Theme.px(22)
                        Accessible.role: Accessible.Slider
                        Accessible.name: Tr.t("Volume") + ": " + Math.round(PlayQueue.volume * 100) + " %"
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: Theme.px(5); radius: Theme.px(3)
                            color: Theme.surface3
                            Rectangle { width: parent.width * (PlayQueue.muted ? 0 : PlayQueue.volume); height: parent.height; radius: Theme.px(3); color: Theme.accent }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function place(x) { PlayQueue.muted = false; PlayQueue.volume = Math.max(0, Math.min(1, x / width)); }
                            onPressed: m => place(m.x)
                            onPositionChanged: m => place(m.x)
                            onWheel: w => win.louder(w.angleDelta.y > 0 ? 0.05 : -0.05)
                        }
                        // keys and a controller: Left / Right a step quieter / louder
                        KeyFocus { slider: true; onStep: dir => win.louder(dir * 0.05) }
                    }
                    IconButton {
                        icon: "document-properties"
                        tip: Tr.t("Media properties")
                        visible: PlayQueue.current !== ""
                        on: win.infoShown
                        onClicked: win.infoShown = !win.infoShown
                    }
                    IconButton {
                        icon: "media-view-subtitles"
                        tip: Tr.t("Sound and subtitles")
                        visible: player.audioTracks.length > 1 || player.subtitleTracks.length > 0 || win.cues.length > 0
                        on: win.tracksShown
                        onClicked: win.tracksShown = !win.tracksShown
                    }
                    IconButton { icon: "view-list"; tip: Tr.t("Queue") + " (L)"; on: win.listShown; onClicked: win.listShown = !win.listShown }
                    IconButton { icon: "document-open-recent"; tip: Tr.t("Recent media"); on: win.recentShown; onClicked: { win.recentShown = !win.recentShown; if (win.recentShown) win.streamShown = false; } }
                    IconButton { icon: "network-workgroup"; tip: Tr.t("Open network stream"); on: win.streamShown; onClicked: { win.streamShown = !win.streamShown; if (win.streamShown) win.recentShown = false; } }
                    IconButton { icon: "document-save-as"; tip: Tr.t("Convert this file…"); enabled: PlayQueue.current !== ""; onClicked: { Ui.converterFiles = [PlayQueue.current]; Ui.converter = true; } }
                    IconButton { icon: "document-open"; tip: Tr.t("Open") + " (O)"; onClicked: win.pick() }
                    IconButton { icon: "view-restore"; tip: Tr.t("Mini player") + " (I)"; enabled: PlayQueue.current !== ""; onClicked: win.setMini(true) }
                    IconButton { icon: "view-fullscreen"; tip: Tr.t("Full screen") + " (F)"; onClicked: Niri.action("fullscreen-window") }
                }
            }

            // ---- the queue: the folder's other files ----
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: Theme.px(280)
                visible: win.listShown && !win.mini
                color: Theme.surface1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(10)
                    spacing: Theme.px(6)
                    RowLayout {
                        Layout.fillWidth: true
                        SectionTitle { Layout.fillWidth: true; text: Tr.t("Queue") + "  ·  " + PlayQueue.queue.length }
                        Button { text: Tr.t("Clear"); flat: true; enabled: PlayQueue.queue.length > 0; onClicked: PlayQueue.clear() }
                    }
                    ListView {
                        reuseItems: true
                        cacheBuffer: 400
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
                            height: Theme.px(32)
                            radius: Theme.radiusSmall
                            color: now ? Theme.accentSoft : rowArea.containsMouse ? Theme.hover : "transparent"
                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.split("/").pop()
                            Accessible.onPressAction: PlayQueue.go(index)
                            Text {
                                anchors { left: parent.left; right: parent.right; leftMargin: Theme.px(8); rightMargin: Theme.px(34); verticalCenter: parent.verticalCenter }
                                text: row.modelData.split("/").pop()
                                color: row.now ? Theme.text : Theme.dim
                                elide: Text.ElideMiddle
                                font.family: Theme.font
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                            }
                            MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: PlayQueue.go(row.index) }
                            KeyFocus { onActivated: PlayQueue.go(row.index) }   // keys and a controller: play this one
                            IconButton {
                                width: parent.height; height: parent.height
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Theme.px(2) }
                                size: Theme.px(18)
                                icon: "list-remove"
                                tip: Tr.t("Remove from the queue")
                                onClicked: PlayQueue.remove(row.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
