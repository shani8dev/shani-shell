// On-screen display for volume, mic, brightness and keyboard layout: a pill
// above the dock on the focused screen, for 1.4 s after the change. It reacts
// to the change itself (a key, a slider, `wpctl` in a terminal), not to the
// keybind, so nothing has to remember to show it. Startup values are not
// changes, so nothing shows while services are still settling.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Scope {
    id: root
    property string icon
    property real value: -1          // < 0: no bar (a label instead)
    property string label
    property bool shown: false
    property bool armed: false

    function show(icon, value, label) {
        if (!armed)
            return;
        root.icon = icon;
        root.value = value;
        root.label = label || "";
        shown = true;
        hide.restart();
    }

    Timer { interval: 2500; running: true; onTriggered: root.armed = true }
    Timer { id: hide; interval: 1400; onTriggered: root.shown = false }

    Connections {
        target: Audio
        function onVolumeChanged() { root.show(Audio.icon, Audio.volume); }
        function onMutedChanged() { root.show(Audio.icon, Audio.muted ? 0 : Audio.volume); }
        function onMicMutedChanged() {
            root.show(Audio.micMuted ? "microphone-sensitivity-muted" : "audio-input-microphone", -1,
                      Audio.micMuted ? "Microphone off" : "Microphone on");
        }
    }
    Connections {
        target: Brightness
        function onValueChanged() { root.show("display-brightness", Brightness.value); }
    }
    Connections {
        target: Niri
        function onLayoutIndexChanged() { root.show("input-keyboard", -1, Niri.layout); }
    }

    PanelWindow {
        visible: root.shown && !Lock.locked
        screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
        anchors.bottom: true
        margins.bottom: 110
        implicitWidth: pill.width
        implicitHeight: pill.height
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shani-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        BackgroundEffect.blurRegion: Settings.data.blur ? osdRegion : null
        Region { id: osdRegion; item: pill; radius: pill.radius }

        Glass {
            id: pill
            strong: true
            width: 300
            height: 52
            radius: 26
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12
                Icon { name: root.icon; size: 20 }
                Rectangle {
                    visible: root.value >= 0
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Theme.hover
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.value))
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 90 } }
                    }
                }
                Text {
                    visible: root.value >= 0
                    text: Math.round(root.value * 100)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                    Layout.preferredWidth: 26
                    horizontalAlignment: Text.AlignRight
                }
                Text {
                    visible: root.value < 0
                    Layout.fillWidth: true
                    text: root.label
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }
        }
    }
}
