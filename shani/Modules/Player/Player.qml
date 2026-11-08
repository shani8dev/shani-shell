// The player surface: now playing with album art, controls and a source
// picker (one card like the Islands's, but made to be stood at rather than
// glimpsed). Follows Media.current; the source list lets you follow any of
// Media.players instead (remembered in Settings.preferredPlayer).
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
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
    onPlayerChanged: shown = player ? player.position : 0
    Timer {
        interval: 900
        running: win.visible && win.player && win.player.isPlaying
        repeat: true
        onTriggered: win.shown = win.player.position
    }

    function fmt(s) { return Math.floor(s / 60) + ":" + String(Math.floor(s % 60)).padStart(2, "0"); }

    MouseArea { anchors.fill: parent; onClicked: Ui.player = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.player = false }

    Glass {
        id: card
        anchors.centerIn: parent
        width: 420
        implicitHeight: col.implicitHeight + 32
        strong: true
        radius: Theme.radiusLarge

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SectionTitle {
                    Layout.fillWidth: true
                    text: Tr.t("Now playing")
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
                subtitle: Tr.t("Start music or video in any app, and it shows here")
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
                        source: win.player ? (win.player.trackArtUrl || win.player.artUrl || "") : ""
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
                        text: win.player ? (win.player.trackArtist || win.player.identity || "") : ""
                        color: Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
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

            // seek: click along the track (only when the player allows it)
            Rectangle {
                id: seek
                Layout.fillWidth: true
                visible: win.player !== null
                implicitHeight: 26
                color: "transparent"
                readonly property real len: win.player ? win.player.length : 0
                readonly property bool seekable: win.player && win.player.canSeek && len > 0
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
                Text {
                    anchors { left: parent.left; bottom: parent.bottom }
                    text: win.player ? win.fmt(win.shown) : "0:00"
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
                    onClicked: me => win.player.position = win.player.length * (me.x / parent.width)
                }
                KeyFocus {
                    name: Tr.t("Position")
                    slider: true
                    onStep: dir => { if (win.player) win.player.position = Math.max(0, Math.min(win.player.length, win.shown + dir * 10)); }
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
                text: Tr.t("Esc closes · Left/Right seeks 10s")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }
}
