// Layout Switcher — desktop style picker (Manjaro reference image style)
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common

PanelWindow {
    id: root
    property bool active: Ui.layoutSwitcher
    visible: active
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-layout-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property string currentPreset: Settings.data.layoutPreset || "default"

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Ui.layoutSwitcher = false;
            event.accepted = true;
        }
    }

    function applyPreset(preset) {
        const p = preset || currentPreset || "default";
        currentPreset = p;
        Settings.data.layoutPreset = p;
        if (p === "default") {
            // Restore default mixed layout (bar + dock, like current)
            Settings.data.desktopWidgets = ["clock"];
            Settings.data.dock = true;
            Settings.data.dockAutoHide = false;
            return;
        }
        // Desktop widgets per preset (generic, like Deepin)
        if (p === "windows" || p === "windows11" || p === "classic") {
            Settings.data.desktopWidgets = ["clock", "media", "weather", "stats"];
        } else if (p === "macos" || p === "macos-like") {
            Settings.data.desktopWidgets = ["clock", "media"];
        } else if (p === "unity" || p === "ubuntu") {
            Settings.data.desktopWidgets = ["clock"];
        } else if (p === "gnome") {
            Settings.data.desktopWidgets = ["clock"];
        } else if (p === "elementary" || p === "pantheon") {
            Settings.data.desktopWidgets = ["clock", "media"];
        } else if (p === "chromeos" || p === "chromebook") {
            Settings.data.desktopWidgets = ["clock"];
        } else if (p === "tiling" || p === "i3" || p === "dwm") {
            Settings.data.desktopWidgets = [];
        } else {
            Settings.data.desktopWidgets = ["clock"];
        }
        // Dock/panel per preset (Deepin-style)
        if (p === "tiling" || p === "i3" || p === "dwm") {
            Settings.data.dock = false;
            Settings.data.dockAutoHide = true;
        } else if (p === "unity" || p === "ubuntu") {
            Settings.data.dock = true;
            Settings.data.dockAutoHide = true;
        } else if (p === "chromeos" || p === "chromebook") {
            Settings.data.dock = true;
            Settings.data.dockAutoHide = false;
        } else if (p === "macos" || p === "macos-like") {
            Settings.data.dock = true;
            Settings.data.dockAutoHide = false;
        } else if (p === "gnome") {
            Settings.data.dock = true;
            Settings.data.dockAutoHide = true;
        } else if (p === "elementary" || p === "pantheon") {
            Settings.data.dock = true;
            Settings.data.dockAutoHide = false;
        } else if (p === "windows" || p === "windows11" || p === "classic") {
            Settings.data.dock = true;
            Settings.data.dockAutoHide = false;
        } else {
            Settings.data.dock = true;
            Settings.data.dockAutoHide = false;
        }
    }

    Rectangle {
        id: overlay
        anchors.fill: parent
        color: "black"
        opacity: root.visible ? 0.4 : 0

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            onClicked: Ui.layoutSwitcher = false
            enabled: root.visible
        }
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 720)
        height: Math.min(parent.height - 80, 520)
        radius: Theme.radiusLarge
        strong: true
        opacity: root.visible ? 1 : 0
        scale: root.visible ? 1 : 0.95

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            onClicked: {} // prevent closing when clicking card
            propagateComposedEvents: false
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: Tr.t("Layout Switcher")
                font.family: Theme.font
                font.pixelSize: 18 * Theme.fontScale
                font.weight: Font.Bold
                color: Theme.text
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Button { text: Tr.t("Layout"); onClicked: {} }
                Button { text: Tr.t("Settings"); onClicked: { Ui.layoutSwitcher = false; Ui.openSettings("look"); } }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 300
                columns: 3
                rowSpacing: 12
                columnSpacing: 12
                Repeater {
                    model: [
                        { name: "Default", desc: "Current mixed layout (bar + dock)", preset: "default" },
                        { name: "Windows 11", desc: "Taskbar with Start menu style", preset: "windows" },
                        { name: "macOS", desc: "Dock at bottom, clean layout", preset: "macos" },
                        { name: "Ubuntu", desc: "Ubuntu-style with dock", preset: "ubuntu" },
                        { name: "Unity", desc: "Unity launcher and dock", preset: "unity" },
                        { name: "GNOME", desc: "Minimal dock, top bar focused", preset: "gnome" },
                        { name: "Elementary", desc: "Clean elegant layout", preset: "elementary" },
                        { name: "ChromeOS", desc: "Shelf at bottom", preset: "chromeos" },
                        { name: "Tiling", desc: "Window tiling, no dock", preset: "tiling" }
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radius
                        color: root.currentPreset === modelData.preset ? Theme.accent : Theme.bg
                        opacity: root.currentPreset === modelData.preset ? 0.15 : 1.0
                        border.color: root.currentPreset === modelData.preset ? Theme.accent : Theme.stroke
                        border.width: root.currentPreset === modelData.preset ? 2 : 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Behavior on border.width { NumberAnimation { duration: 150 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            Text {
                                text: modelData.name
                                font.family: Theme.font
                                font.pixelSize: 13 * Theme.fontScale
                                font.weight: Font.Medium
                                color: Theme.text
                            }
                            Text {
                                text: modelData.desc
                                font.family: Theme.font
                                font.pixelSize: 9 * Theme.fontScale
                                color: Theme.dim
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.applyPreset(modelData.preset);
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12
                Button {
                    text: Tr.t("Reload Desktop")
                    onClicked: { root.applyPreset(root.currentPreset); Ui.layoutSwitcher = false; }
                }
                Button {
                    text: Tr.t("Apply")
                    onClicked: Ui.layoutSwitcher = false
                }
                Button {
                    text: Tr.t("Cancel")
                    onClicked: Ui.layoutSwitcher = false
                }
            }
        }
    }
}
