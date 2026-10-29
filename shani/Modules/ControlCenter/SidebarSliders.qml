// The control centre's sliders (one section of Sidebar.qml).
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

    SliderRow {
        Layout.fillWidth: true
        icon: Audio.icon
        value: Audio.volume / Audio.maxVolume
        muted: Audio.muted
        hasDetail: true
        expanded: Ui.expanded === "audio"
        onMoved: v => Audio.setVolume(v * Audio.maxVolume)
        onIconClicked: Audio.toggleMute()
        onDetail: Ui.expanded = Ui.expanded === "audio" ? "" : "audio"
    }
    SliderRow {
        Layout.fillWidth: true
        visible: Audio.source !== null
        icon: Audio.micMuted ? "microphone-sensitivity-muted" : "audio-input-microphone"
        value: Audio.micVolume
        muted: Audio.micMuted
        level: micLevel.enabled ? Math.min(1, micLevel.peak * 1.5) : -1
        hasDetail: true
        expanded: Ui.expanded === "audio"
        onMoved: v => Audio.setMicVolume(v)
        onIconClicked: Audio.toggleMic()
        onDetail: Ui.expanded = Ui.expanded === "audio" ? "" : "audio"
        PwNodePeakMonitor {
            id: micLevel
            node: Audio.source
            enabled: sidebar.visible && Ui.controlCenter && !Audio.micMuted
        }
    }
    SliderRow {
        Layout.fillWidth: true
        visible: Brightness.available
        icon: "display-brightness"
        value: Brightness.value
        onMoved: v => Brightness.set(v)
    }

    ColumnLayout {
        visible: Ui.expanded === "audio"
        Layout.fillWidth: true
        spacing: 2
        SectionTitle { text: Tr.t("Output") }
        Repeater {
            model: Audio.sinks
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "audio-speakers"
                title: Audio.nodeName(modelData)
                selected: modelData === Audio.sink
                onClicked: Audio.useSink(modelData)
            }
        }
        SectionTitle { visible: Audio.players.length > 0; text: Tr.t("Apps") }
        Repeater {
            model: Audio.players
            SliderRow {
                required property var modelData
                Layout.fillWidth: true
                icon: modelData.audio && modelData.audio.muted ? "audio-volume-muted" : "audio-volume-high"
                value: modelData.audio ? modelData.audio.volume : 0
                muted: modelData.audio ? modelData.audio.muted : false
                onMoved: v => modelData.audio.volume = v
                onIconClicked: modelData.audio.muted = !modelData.audio.muted
                Text {
                    text: Audio.streamName(modelData)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                    Layout.maximumWidth: 90
                    elide: Text.ElideRight
                }
            }
        }
        SectionTitle { text: Tr.t("Input") }
        Repeater {
            model: Audio.sources
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "audio-input-microphone"
                title: Audio.nodeName(modelData)
                selected: modelData === Audio.source
                onClicked: Audio.useSource(modelData)
            }
        }
    }
}
