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
    // a section whose parts are all hidden takes no room (no double gap)
    visible: Array.from(children).some(c => c.visible)

    Glass {
        visible: sidebar.player !== null
        Layout.fillWidth: true
        implicitHeight: 92
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
                    Layout.fillWidth: true
                    text: sidebar.player ? sidebar.player.trackArtist : ""
                    color: Theme.dim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
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
                Row {
                    spacing: 4
                    IconButton { icon: "media-skip-backward"; size: 28; onClicked: sidebar.player.previous() }
                    IconButton { icon: sidebar.player && sidebar.player.isPlaying ? "media-playback-pause" : "media-playback-start"; size: 28; on: true; onClicked: sidebar.player.togglePlaying() }
                    IconButton { icon: "media-skip-forward"; size: 28; onClicked: sidebar.player.next() }
                }
            }
        }
    }
}
