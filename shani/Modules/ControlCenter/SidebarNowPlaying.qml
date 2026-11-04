// The control centre's now playing (one section of Sidebar.qml).
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import Quickshell.Bluetooth
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Notifications

ColumnLayout {
    required property var sidebar
    spacing: 14

    Glass {
        id: np
        visible: sidebar.player !== null
        // a wash of the cover's own colour (dux's): the most vivid of a few candidates
        ColorQuantizer {
            id: art
            source: sidebar.visible && sidebar.player && sidebar.player.trackArtUrl ? sidebar.player.trackArtUrl : ""
            depth: 2
            rescaleSize: 48
        }
        readonly property var artTint: {
            let best = null;
            for (const c of art.colors || [])
                if (c.hslSaturation > 0.25 && c.hslLightness > 0.15 && c.hslLightness < 0.85 && (!best || c.hslSaturation > best.hslSaturation))
                    best = c;
            return best;
        }
        color: artTint ? Qt.tint(opaque ? Theme.bg : Theme.glass, Theme.alpha(artTint, 0.20)) : (opaque ? Theme.bg : Theme.glass)
        Layout.fillWidth: true
        implicitHeight: 118
        // the track's position, sampled while it plays (the thin bar moves)
        property real shown: sidebar.player ? sidebar.player.position : 0
        Timer {
            interval: 900
            running: sidebar.visible && sidebar.player && sidebar.player.isPlaying
            repeat: true
            onTriggered: parent.shown = sidebar.player.position
        }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            ClippingRectangle {
                implicitWidth: 66
                implicitHeight: 66
                radius: 10
                color: Theme.hover
                Image {
                    anchors.fill: parent
                    source: sidebar.player ? sidebar.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: sidebar.player ? (sidebar.player.trackTitle || sidebar.player.identity) : ""
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: Media.players.length > 1
                    Layout.fillWidth: true
                    text: (sidebar.player ? sidebar.player.identity : "") + "  ⇄"
                    color: Theme.accent
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                    Accessible.role: Accessible.Button
                    Accessible.name: Tr.t("Switch player (now %1)").arg(sidebar.player ? sidebar.player.identity : "")
                    Accessible.onPressAction: Media.cycle()
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Media.cycle() }
                    Hint { text: Tr.t("Follow the next player") }
                }
                Text {
                    Layout.fillWidth: true
                    text: sidebar.player ? sidebar.player.trackArtist : ""
                    color: Theme.dim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                // seek: click along the track (only when the player allows it)
                Rectangle {
                    id: seek
                    visible: sidebar.player && sidebar.player.canSeek && sidebar.player.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 13
                    color: "transparent"
                    readonly property real len: sidebar.player ? sidebar.player.length : 0
                    Text {
                        anchors { left: parent.left; bottom: parent.bottom }
                        text: Math.floor(np.shown / 60) + ":" + String(Math.floor(np.shown % 60)).padStart(2, "0")
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: 9 * Theme.fontScale
                    }
                    Text {
                        anchors { right: parent.right; bottom: parent.bottom }
                        text: Math.floor(parent.len / 60) + ":" + String(Math.floor(parent.len % 60)).padStart(2, "0")
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: 9 * Theme.fontScale
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        height: 3
                        radius: 1.5
                        color: Theme.hover
                    }
                    Rectangle {
                        width: Math.max(3, parent.width * Math.min(1, parent.len > 0 ? np.shown / parent.len : 0))
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        height: 3
                        radius: 1.5
                        color: Theme.accent
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: me => sidebar.player.position = sidebar.player.length * (me.x / parent.width)
                    }
                }
                Row {
                    spacing: 4
                    // the output level over the last second and a half
                    Row {
                        id: meter
                        spacing: 2
                        height: 14
                        property var history: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
                        PwNodePeakMonitor {
                            id: outLevel
                            node: Audio.sink
                            enabled: sidebar.visible && sidebar.player !== null && sidebar.player.isPlaying
                        }
                        Timer {
                            interval: 80
                            running: outLevel.enabled
                            repeat: true
                            onTriggered: meter.history = meter.history.slice(1).concat([Math.min(1, outLevel.peak * 1.5)])
                        }
                        Repeater {
                            model: meter.history
                            Rectangle {
                                required property real modelData
                                width: 4
                                height: Math.max(2, modelData * meter.height)
                                anchors.bottom: parent ? parent.bottom : undefined
                                radius: 2
                                color: Theme.alpha(Theme.accent, 0.4 + modelData * 0.6)
                            }
                        }
                    }
                    IconButton { icon: "media-skip-backward"; size: 28; onClicked: sidebar.player.previous() }
                    IconButton { icon: sidebar.player && sidebar.player.isPlaying ? "media-playback-pause" : "media-playback-start"; size: 28; on: true; onClicked: sidebar.player.togglePlaying() }
                    IconButton { icon: "media-skip-forward"; size: 28; onClicked: sidebar.player.next() }
                }
            }
        }
    }
}
