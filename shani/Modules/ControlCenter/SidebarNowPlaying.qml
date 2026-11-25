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
import "../../Common/Time.js" as Time

ColumnLayout {
    required property var sidebar
    spacing: Theme.px(14)

    Glass {
        id: np
        visible: sidebar.player !== null
        // a wash of the cover's own colour: the most vivid of a few candidates
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
        implicitHeight: 118 + (lyricLine.visible ? 24 : 0)
        // the card asks for lyrics only while it is on screen
        Binding { target: Lyrics; property: "wanted"; value: sidebar.visible && np.visible }
        // the track's position, sampled while it plays (the thin bar moves)
        property real shown: sidebar.player ? sidebar.player.position : 0
        Timer {
            running: sidebar.visible && sidebar.player && sidebar.player.isPlaying
            repeat: true
            interval: Lyrics.lines.length ? 400 : 900
            onTriggered: parent.shown = sidebar.player.position
        }
        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            anchors.bottomMargin: 12 + (lyricLine.visible ? 24 : 0)
            spacing: Theme.px(12)
            ClippingRectangle {
                implicitWidth: Theme.px(66)
                implicitHeight: Theme.px(66)
                radius: Theme.px(10)
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
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: Media.players.length > 1
                    Layout.fillWidth: true
                    text: (sidebar.player ? sidebar.player.identity : "") + "  ⇄"
                    color: Theme.accent
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                    Accessible.role: Accessible.Button
                    Accessible.name: Tr.t("Switch player (now %1)").arg(sidebar.player ? sidebar.player.identity : "")
                    Accessible.onPressAction: Media.cycle()
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Media.cycle() }
                    KeyFocus { onActivated: Media.cycle() }
                    Hint { text: Tr.t("Follow the next player") }
                }
                Text {
                    Layout.fillWidth: true
                    text: sidebar.player ? sidebar.player.trackArtist : ""
                    color: Theme.dim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                // seek: click along the track (only when the player allows it)
                Rectangle {
                    id: seek
                    visible: sidebar.player && sidebar.player.canSeek && sidebar.player.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(13)
                    color: "transparent"
                    readonly property real len: sidebar.player ? sidebar.player.length : 0
                    // Qt reads a Slider's value off the object's own `value`
                    // property - assigning Accessible.value would be an error
                    property real value: len > 0 ? np.shown / len : 0
                    Accessible.role: Accessible.Slider
                    Accessible.name: Tr.t("Position") + " " + Time.clockLong(np.shown)
                        + " / " + Time.clockLong(len)
                    Text {
                        anchors { left: parent.left; bottom: parent.bottom }
                        text: Time.clock(np.shown)
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(9) * Theme.fontScale
                        Accessible.name: Tr.t("Elapsed %1").arg(text)
                    }
                    Text {
                        anchors { right: parent.right; bottom: parent.bottom }
                        text: Time.clock(parent.len)
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(9) * Theme.fontScale
                        Accessible.name: Tr.t("Total %1").arg(text)
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        height: Theme.px(3)
                        radius: 1.5
                        color: Theme.hover
                    }
                    Rectangle {
                        width: Math.max(3, parent.width * Math.min(1, parent.len > 0 ? np.shown / parent.len : 0))
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        height: Theme.px(3)
                        radius: 1.5
                        color: Theme.accent
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        // follow the pointer while held, not only on release: dragging scrubs
                        function seekTo(x) {
                            const pos = Math.max(0, Math.min(len, len * (x / width)));
                            sidebar.player.position = pos;
                            np.shown = pos;   // keep the bar honest while paused (its timer is off)
                        }
                        onPressed: me => seekTo(me.x)
                        onPositionChanged: me => { if (pressed) seekTo(me.x); }
                        onClicked: me => seekTo(me.x)
                    }
                    // keyboard and controller: Left / Right seek 10 s
                    KeyFocus {
                        name: Tr.t("Position")
                        slider: true
                        onStep: dir => {
                            const pos = Math.max(0, Math.min(sidebar.player.length, sidebar.player.position + dir * 10));
                            sidebar.player.position = pos;
                            np.shown = pos;
                        }
                    }
                }
                Row {
                    spacing: Theme.px(4)
                    // the output level over the last second and a half
                    Row {
                        id: meter
                        spacing: 2
                        height: Theme.px(14)
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
                                width: Theme.px(4)
                                height: Math.max(2, modelData * meter.height)
                                anchors.bottom: parent ? parent.bottom : undefined
                                radius: 2
                                color: Theme.alpha(Theme.accent, 0.4 + modelData * 0.6)
                            }
                        }
                    }
                    IconButton { icon: "media-skip-backward"; tip: Tr.t("Previous"); size: Theme.px(28); onClicked: sidebar.player.previous() }
                    IconButton { icon: sidebar.player && sidebar.player.isPlaying ? "media-playback-pause" : "media-playback-start"; tip: sidebar.player && sidebar.player.isPlaying ? Tr.t("Pause") : Tr.t("Play"); size: Theme.px(28); on: true; onClicked: sidebar.player.togglePlaying() }
                    IconButton { icon: "media-skip-forward"; tip: Tr.t("Next"); size: Theme.px(28); onClicked: sidebar.player.next() }
                    IconButton { visible: sidebar.player && sidebar.player.canRaise; icon: "window-new"; size: Theme.px(28); tip: Tr.t("Show the player"); onClicked: { Ui.closeAll(); sidebar.player.raise(); } }
                }
            }
        }
        // the line being sung, under the controls
        Text {
            id: lyricLine
            readonly property string line: Lyrics.lineAt(np.shown)
            visible: Lyrics.lines.length > 0
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.px(10) }
            horizontalAlignment: Text.AlignHCenter
            text: line || "♪"
            color: Theme.text
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
            font.italic: true
        }
    }
}
