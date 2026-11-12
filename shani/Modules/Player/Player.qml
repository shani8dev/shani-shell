// The player surface: now playing with album art, controls, a seek bar
// and a folder queue (Decibels parity). Follows Media.current; the source
// list lets you follow any of Media.players instead (remembered in
// Settings.preferredPlayer). The queue scans a music folder for audio
// files; clicking one opens it in the current player (openUri), or with the
// system opener when no player is running — the panel stays usable with
// no player at all. The MPRIS TrackList interface is where available;
// Quickshell does not expose it yet, so the folder queue is the fallback.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.player && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-player"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurRegion : null
    Region { id: blurRegion; item: card; radius: Theme.radiusLarge }

    readonly property var player: Media.current
    // the track's position, sampled while it plays (the bar moves)
    property real shown: player ? player.position : 0
    property bool dragging: false
    onPlayerChanged: shown = player ? player.position : 0
    onVisibleChanged: { Lyrics.wanted = visible; if (visible) win.refreshQueue(); }
    Component.onCompleted: Lyrics.wanted = visible
    Timer {
        interval: 400
        running: win.visible && win.player && win.player.isPlaying && !win.dragging
        repeat: true
        onTriggered: win.shown = win.player.position
    }

    // folder queue: [{ path, name }] sorted by name, 200 files max
    property string musicFolder: win.defaultMusicFolder()
    property var queue: []
    property string queueNote: ""
    // the MPRIS tracklist, where a player exposes it; Quickshell does not
    // surface the TrackList interface yet, so this stays null and the
    // folder queue above is what is shown
    readonly property var tracklistItems: win.player ? win.player.tracklist : null
    readonly property bool hasTracklist: !!win.tracklistItems && win.tracklistItems.length > 0
    readonly property int currentQueueIndex: {
        if (!win.player || !win.queue.length)
            return -1;
        const url = (win.player.metadata && win.player.metadata["xesam:url"]) || "";
        const title = (win.player.trackTitle || "").toLowerCase();
        for (let i = 0; i < win.queue.length; i++) {
            const p = win.queue[i];
            if (url && (url.indexOf(p.path) >= 0 || url.endsWith(p.name)))
                return i;
            if (title && p.name.toLowerCase().indexOf(title) >= 0)
                return i;
        }
        return -1;
    }

    function defaultMusicFolder() {
        const xdg = Quickshell.env("XDG_MUSIC_DIR");
        if (xdg)
            return xdg;
        const home = Quickshell.env("HOME") || "";
        return home ? home + "/Music" : "";
    }
    function fmt(s) { return Math.floor(s / 60) + ":" + String(Math.floor(s % 60)).padStart(2, "0"); }
    function fmtRemaining(pos, len) { return "-" + win.fmt(Math.max(0, len - pos)); }
    function seekTo(frac) {
        if (!win.player || !win.player.canSeek || win.player.length <= 0)
            return;
        const v = Math.max(0, Math.min(1, frac)) * win.player.length;
        win.shown = v;
        win.player.position = v;
    }
    function cycleRepeat() {
        if (!win.player || !win.player.loopSupported || !win.player.canControl)
            return;
        if (win.player.loopState === MprisLoopState.None)
            win.player.loopState = MprisLoopState.Playlist;
        else if (win.player.loopState === MprisLoopState.Playlist)
            win.player.loopState = MprisLoopState.Track;
        else
            win.player.loopState = MprisLoopState.None;
    }
    function toggleShuffle() {
        if (!win.player || !win.player.shuffleSupported || !win.player.canControl)
            return;
        win.player.shuffle = !win.player.shuffle;
    }
    function refreshQueue() {
        win.queue = [];
        win.queueNote = "";
        listQueue.running = true;
    }
    function openQueueItem(path) {
        if (!path)
            return;
        if (win.player && win.player.openUri)
            win.player.openUri("file://" + encodeURI(path));
        else
            Quickshell.execDetached(["xdg-open", path]);
    }
    function trimPath() {
        const i = win.currentQueueIndex;
        if (i >= 0 && win.queue[i] && win.queue[i].path)
            return win.queue[i].path;
        const url = (win.player && win.player.metadata && win.player.metadata["xesam:url"]) || "";
        return url ? url.replace(/^file:\/\//, "") : "";
    }
    function openTrim() {
        const p = win.trimPath();
        if (p) {
            Ui.closeAll();
            VideoTrimmer.open(p);
        }
    }
    function repeatLabel() {
        if (!win.player || !win.player.loopSupported)
            return Tr.t("Repeat not supported");
        if (win.player.loopState === MprisLoopState.Track)
            return Tr.t("Repeat one track");
        if (win.player.loopState === MprisLoopState.Playlist)
            return Tr.t("Repeat all");
        return Tr.t("Repeat off");
    }

    Process {
        id: listQueue
        command: ["sh", "-c", 'd="$1"; [ -d "$d" ] || exit 0; find "$d" -maxdepth 1 -type f \\( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.wav" -o -iname "*.m4a" -o -iname "*.aac" \\) 2>/dev/null | sort | head -200', "sh", win.musicFolder]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = text.split("\n");
                for (const line of lines) {
                    const p = line.trim();
                    if (!p)
                        continue;
                    out.push({ path: p, name: p.split("/").pop() });
                }
                win.queue = out;
                win.queueNote = out.length ? "" : Tr.t("No audio files in this folder");
            }
        }
    }

    // made on first use: a native dialog is the desktop portal's, and made
    // with every picker it held the whole shell while D-Bus waited for it
    Loader {
        id: folderDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FolderDialog {
            title: Tr.t("Choose a music folder")
            onAccepted: {
                win.musicFolder = selectedFolder.toString().replace(/^file:\/\//, "");
                win.refreshQueue();
            }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: Ui.player = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.player = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 40)
        height: Math.min(680, parent.height - 80)
        strong: true
        radius: Theme.radiusLarge

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SectionTitle {
                    Layout.fillWidth: true
                    text: Tr.t("Now playing")
                }
                Text {
                    visible: win.hasTracklist
                    text: Tr.t("tracklist")
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 10 * Theme.fontScale
                }
                IconButton {
                    icon: "view-refresh"
                    size: 28
                    tip: Tr.t("Refresh queue")
                    onClicked: win.refreshQueue()
                }
                IconButton {
                    icon: "window-close"
                    size: 28
                    tip: Tr.t("Close")
                    onClicked: Ui.player = false
                }
            }

            EmptyState {
                Layout.fillWidth: true
                visible: win.player === null
                icon: "media-playback-start"
                title: Tr.t("No player")
                subtitle: Tr.t("Start music or video in any app, and it shows here — the queue below still works")
            }

            RowLayout {
                Layout.fillWidth: true
                visible: win.player !== null
                spacing: 12

                ClippingRectangle {
                    implicitWidth: 88
                    implicitHeight: 88
                    radius: 14
                    color: Theme.hover
                    Image {
                        anchors.fill: parent
                        source: win.player ? (win.player.trackArtUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        Accessible.role: Accessible.Graphic
                        Accessible.name: Tr.t("Album art")
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: win.player ? (win.player.trackTitle || win.player.identity || Tr.t("Unknown track")) : ""
                        color: Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 15 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.player ? (win.player.trackArtist || "") : ""
                        color: Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: win.player && win.player.trackAlbum
                        text: win.player ? (win.player.trackAlbum || "") : ""
                        color: Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.player ? (win.player.identity || "") : ""
                        color: Theme.faint
                        elide: Text.ElideRight
                        font.family: Theme.mono
                        font.pixelSize: 10 * Theme.fontScale
                    }
                }
            }

            // seek: drag along the track, with elapsed and remaining times
            Rectangle {
                id: seek
                Layout.fillWidth: true
                visible: win.player !== null
                implicitHeight: 30
                color: "transparent"
                readonly property real len: win.player ? win.player.length : 0
                readonly property bool seekable: win.player ? (win.player.canSeek && len > 0) : false
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: 4
                    radius: 2
                    color: Theme.hover
                }
                Rectangle {
                    width: Math.max(4, parent.width * Math.min(1, seek.len > 0 ? win.shown / seek.len : 0))
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    height: 4
                    radius: 2
                    color: Theme.accent
                }
                Rectangle {
                    x: Math.max(0, Math.min(parent.width - width, parent.width * (seek.len > 0 ? win.shown / seek.len : 0) - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.text
                    border.width: 3
                    border.color: Theme.accent
                    visible: seek.seekable
                }
                Text {
                    anchors { left: parent.left; bottom: parent.bottom }
                    text: win.player ? win.fmt(win.shown) : "0:00"
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 9 * Theme.fontScale
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    visible: win.player !== null
                    text: win.player ? win.fmtRemaining(win.shown, seek.len) : "-0:00"
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 9 * Theme.fontScale
                }
                Text {
                    anchors { right: parent.right; bottom: parent.bottom }
                    text: win.player ? win.fmt(seek.len) : "0:00"
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 9 * Theme.fontScale
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: seek.seekable
                    cursorShape: Qt.PointingHandCursor
                    function at(x) {
                        win.dragging = true;
                        win.shown = seek.len * Math.max(0, Math.min(1, x / width));
                    }
                    onPressed: me => at(me.x)
                    onPositionChanged: me => { if (pressed) at(me.x); }
                    onReleased: me => { win.seekTo(me.x / width); win.dragging = false; }
                }
                KeyFocus {
                    name: Tr.t("Position")
                    slider: true
                    onStep: dir => { if (win.player) win.seekTo(Math.max(0, Math.min(1, (win.shown + dir * 10) / Math.max(1, win.player.length)))); }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: win.player !== null && !(win.player && win.player.canSeek && win.player.length > 0)
                text: Tr.t("Seeking is not available for this track")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }

            RowLayout {
                Layout.fillWidth: true
                visible: win.player !== null
                Layout.alignment: Qt.AlignHCenter
                spacing: 12
                IconButton {
                    icon: "media-playlist-repeat"
                    size: 36
                    on: win.player ? (win.player.loopSupported && win.player.loopState !== MprisLoopState.None) : false
                    tip: win.repeatLabel()
                    enabled: win.player ? (win.player.loopSupported && win.player.canControl) : false
                    onClicked: win.cycleRepeat()
                }
                IconButton {
                    icon: "media-skip-backward"
                    size: 40
                    tip: Tr.t("Previous track")
                    enabled: win.player && win.player.canGoPrevious
                    onClicked: win.player.previous()
                }
                IconButton {
                    icon: win.player && win.player.isPlaying ? "media-playback-pause" : "media-playback-start"
                    size: 52
                    on: true
                    tip: win.player && win.player.isPlaying ? Tr.t("Pause") : Tr.t("Play")
                    onClicked: win.player.togglePlaying()
                }
                IconButton {
                    icon: "media-skip-forward"
                    size: 40
                    tip: Tr.t("Next track")
                    enabled: win.player && win.player.canGoNext
                    onClicked: win.player.next()
                }
                IconButton {
                    icon: "media-playlist-shuffle"
                    size: 36
                    on: win.player ? win.player.shuffle : false
                    tip: Tr.t("Shuffle")
                    enabled: win.player ? (win.player.shuffleSupported && win.player.canControl) : false
                    onClicked: win.toggleShuffle()
                }
                Button {
                    text: Tr.t("Trim")
                    visible: win.trimPath() !== ""
                    onClicked: win.openTrim()
                }
            }
            Text {
                Layout.fillWidth: true
                visible: win.player !== null && win.player && (!win.player.loopSupported || !win.player.shuffleSupported)
                text: Tr.t("Repeat and shuffle depend on the player — this one does not offer both")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }

            // per-player volume: the followed player's own level
            SliderRow {
                Layout.fillWidth: true
                visible: win.player !== null && win.player && win.player.volumeSupported && win.player.canControl
                icon: "audio-volume-high"
                value: win.player ? win.player.volume : 0
                onMoved: v => { if (win.player) win.player.volume = v; }
            }
            Text {
                Layout.fillWidth: true
                visible: win.player !== null && win.player && !(win.player.volumeSupported && win.player.canControl)
                text: Tr.t("Player volume is not controllable — use the system output")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }

            // gapless and format info: MPRIS does not advertise gapless, so
            // this says so and shows what the player does advertise
            Text {
                Layout.fillWidth: true
                visible: win.player !== null
                wrapMode: Text.Wrap
                text: win.player ? (Tr.t("Gapless: depends on the player engine — MPRIS does not advertise it") + " · "
                    + Tr.t("Rate %1×").arg(win.player.rate || 1) + " · "
                    + Array.from(win.player.supportedMimeTypes || []).slice(0, 3).join(", ")) : ""
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }

            // lyrics: the line being sung, via the Lyrics service (LRCLIB)
            Rectangle {
                Layout.fillWidth: true
                visible: win.player !== null
                radius: 10
                color: Theme.surface1
                implicitHeight: 44
                Text {
                    anchors.fill: parent
                    anchors.margins: 10
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    text: !Settings.data.lyrics
                        ? Tr.t("Enable lyrics in Settings > Sound to see the line being sung")
                        : Lyrics.lines.length ? (Lyrics.lineAt(win.shown) || "♪")
                        : Tr.t("Looking for lyrics…")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                    font.italic: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SectionTitle {
                    Layout.fillWidth: true
                    text: Tr.t("Queue")
                }
                Text {
                    visible: win.queue.length > 0
                    text: Tr.t("%1 files", win.queue.length)
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 10 * Theme.fontScale
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 8
                    color: Theme.surface1
                    border.color: Theme.stroke
                    border.width: 1
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        text: win.musicFolder || Tr.t("No folder")
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 10 * Theme.fontScale
                        elide: Text.ElideMiddle
                    }
                }
                Button {
                    text: Tr.t("Browse")
                    onClicked: folderDlg.open()
                }
            }
            ListView {
                id: queueList
                Layout.fillWidth: true
                Layout.preferredHeight: 130
                clip: true
                spacing: 2
                model: win.queue
                boundsBehavior: Flickable.StopAtBounds
                delegate: ListRow {
                    required property var modelData
                    required property int index
                    width: queueList.width
                    icon: index === win.currentQueueIndex ? "media-playback-start" : "audio-x-generic"
                    title: modelData.name
                    subtitle: modelData.path
                    selected: index === win.currentQueueIndex
                    onClicked: win.openQueueItem(modelData.path)
                }
            }
            Text {
                Layout.fillWidth: true
                visible: win.queue.length === 0 && !listQueue.running
                text: win.queueNote || Tr.t("No audio files in this folder")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }

            SectionTitle {
                Layout.fillWidth: true
                visible: Media.players.length > 0
                text: Tr.t("Source")
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: Media.players.length > 0
                spacing: 2
                Repeater {
                    model: Media.players
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: modelData.isPlaying ? "media-playback-start" : "media-playback-start"
                        title: modelData.identity || modelData.name || Tr.t("Player")
                        subtitle: modelData.trackTitle || ""
                        selected: win.player === modelData
                        onClicked: Settings.data.preferredPlayer = modelData.identity
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: Tr.t("Esc closes · Left/Right seeks 10s · drag the seek bar")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
