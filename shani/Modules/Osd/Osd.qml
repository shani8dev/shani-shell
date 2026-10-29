// On-screen display for volume, mic volume and mute, brightness, adaptive
// brightness, caps/num lock, keyboard layout, power profile, night light, DND,
// caffeine, focus mode, display scale, flashlight and network: a pill above
// the dock on the focused screen, for 1.6 s after the change. It reacts
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
    property string icon: ""
    property real value: -1          // < 0: no bar (a label instead)
    property string label: ""
    property bool shown: false
    property bool armed: false
    property string kind: "slider"   // "slider" | "toggle" | "label" | "icon"

    function show(icon, value, label, kind) {
        if (!armed)
            return;
        root.icon = icon;
        root.value = (value === undefined) ? -1 : value;
        root.label = label || "";
        root.kind = kind || (root.value >= 0 ? "slider" : "label");
        shown = true;
        hide.restart();
    }

    Timer { interval: 2500; running: true; onTriggered: root.armed = true }
    Timer { id: hide; interval: 1600; onTriggered: root.shown = false }

    // ---- Audio / volume ----
    Connections {
        target: Audio
        function onVolumeChanged() { root.show(Audio.icon, Audio.volume, "", "slider"); }
        function onMutedChanged() { root.show(Audio.icon, Audio.muted ? 0 : Audio.volume, Audio.muted ? "Muted" : "", "slider"); }
        function onMicMutedChanged() {
            root.show(Audio.micMuted ? "microphone-sensitivity-muted" : "audio-input-microphone", -1,
                      Audio.micMuted ? "Microphone off" : "Microphone on", "toggle");
        }
        function onMicVolumeChanged() {
            root.show("audio-input-microphone", Audio.micVolume, "", "slider");
        }
    }

    // ---- Brightness ----
    Connections {
        target: Brightness
        function onValueChanged() { if (!Brightness.automatic) root.show("display-brightness", Brightness.value, "", "slider"); }
    }

    // ---- Adaptive brightness ----
    Connections {
        target: AmbientLight
        function onAvailableChanged() {
            root.show("display-brightness-auto", -1,
                      AmbientLight.available ? "Ambient light sensor found" : "No ambient light sensor", "label");
        }
        function onEnabledChanged() {
            const what = AmbientLight.available ? "Ambient brightness" : "Adaptive brightness";
            root.show("display-brightness-auto", -1,
                      AmbientLight.enabled ? what + " on" : what + " off", "toggle");
        }
        function onTargetBrightnessChanged() {
            if (AmbientLight.available && AmbientLight.enabled) {
                root.show("display-brightness", AmbientLight.targetBrightness,
                          Math.round(AmbientLight.targetBrightness * 100) + "%", "slider");
            }
        }
    }

    // ---- Caps Lock / Num Lock (the keyboard may have no light for them) ----
    Connections {
        target: LockKeys
        function onCapsChanged() { if (LockKeys.known) root.show("input-keyboard", -1, LockKeys.caps ? "Caps Lock on" : "Caps Lock off", "toggle"); }
        function onNumChanged() { if (LockKeys.known) root.show("input-keyboard", -1, LockKeys.num ? "Num Lock on" : "Num Lock off", "toggle"); }
    }

    // ---- Keyboard layout ----
    Connections {
        target: Niri
        function onLayoutIndexChanged() { root.show("input-keyboard", -1, Niri.layout, "label"); }
    }

    // ---- Power profile ----
    Connections {
        target: Power
        function onProfileChanged() {
            root.show(Power.profileIcon, -1, Power.profileName, "label");
        }
    }

    // ---- Night light ----
    Connections {
        target: NightLight
        function onActiveChanged() {
            root.show("night-light", -1,
                      NightLight.active ? "Night light on" : "Night light off", "toggle");
        }
    }

    // ---- Do not disturb ----
    Connections {
        target: Notifs
        function onDndChanged() {
            root.show("notifications-disabled", -1,
                      Notifs.dnd ? "Do not disturb on" : "Do not disturb off", "toggle");
        }
    }

    // ---- Caffeine ----
    Connections {
        target: Idle
        function onCaffeineChanged() {
            root.show("preferences-desktop-screensaver", -1,
                      Idle.caffeine ? "Caffeine on" : "Caffeine off", "toggle");
        }
    }

    // ---- Focus mode ----
    Connections {
        target: Focus
        function onActiveChanged() {
            root.show("focus-windows", -1,
                      Focus.on ? "Focus: " + Focus.active : "Focus off", "label");
        }
    }

    // ---- Display scale ----
    // A new monitor or an output refresh is not a scale change; remember the
    // focused output's last scale and show only when it moved.
    property real lastScale: -1
    Connections {
        target: Displays
        function onOutputsChanged() {
            const o = Displays.outputs.find(x => x.name === Niri.focusedOutput);
            if (!o) {
                root.lastScale = -1;
                return;
            }
            if (root.lastScale >= 0 && Math.abs(o.scale - root.lastScale) > 0.01)
                root.show("zoom-in", -1, "Scale: " + o.scale + "x", "label");
            root.lastScale = o.scale;
        }
    }

    // ---- Torch/flashlight ----
    Connections {
        target: Brightness
        function onTorchOnChanged() {
            root.show("weather-clear", -1,
                      Brightness.torchOn ? "Flashlight on" : "Flashlight off", "toggle");
        }
    }

    // ---- Network ----
    Connections {
        target: Net
        function onOnlineChanged() {
            root.show(Net.online ? "network-wireless" : "network-wireless-offline", -1,
                      Net.online ? "Connected" : "Disconnected", "label");
        }
    }

    // ---- Battery saver ----
    Connections {
        target: Power
        function onLowAndDischargingChanged() {
            if (Power.lowAndDischarging) {
                root.show("power-profile-power-saver", -1, "Battery saver on", "toggle");
            }
        }
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
            scale: root.shown ? 1 : 0.9
            Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }
            width: 320
            height: 52
            radius: 26
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12

                Icon { name: root.icon; size: 20 }

                // Slider bar (for volume, mic volume, brightness)
                Rectangle {
                    visible: root.kind === "slider"
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

                // Percentage text (for sliders)
                Text {
                    visible: root.kind === "slider"
                    text: Math.round(root.value * 100) + "%"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                    Layout.preferredWidth: 26
                    horizontalAlignment: Text.AlignRight
                }

                // Toggle indicator
                Rectangle {
                    visible: root.kind === "toggle"
                    Layout.preferredWidth: 36
                    height: 20
                    radius: 10
                    color: root.label.indexOf(" on") >= 0 ? Theme.accent : Theme.hover
                    Rectangle {
                        x: root.label.indexOf(" on") >= 0 ? parent.width - width - 2 : 2
                        y: 2
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.text
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                }

                // Label text (for labels and toggles)
                Text {
                    visible: root.kind === "label" || root.kind === "toggle"
                    Layout.fillWidth: true
                    text: root.label
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                    elide: Text.ElideRight
                }
            }
        }
    }
}
