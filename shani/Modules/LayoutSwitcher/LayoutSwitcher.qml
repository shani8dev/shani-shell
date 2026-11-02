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
    screen: {
        try {
            if (typeof Niri !== "undefined" && Niri.focusedOutput) {
                const s = Quickshell.screens.find(x => x.name === Niri.focusedOutput);
                if (s) return s;
            }
        } catch(e) {}
        return Quickshell.screens[0];
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-layout-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property string currentPreset: (Settings.loaded && Settings.data.layoutPreset) ? Settings.data.layoutPreset : "default"
    property string previousPreset: (Settings.loaded && Settings.data.layoutPreset) ? Settings.data.layoutPreset : "default"
    readonly property var presets: [
        { name: Tr.t("Default"), desc: Tr.t("Current mixed layout (bar + dock)"), preset: "default" },
        { name: Tr.t("Windows 11"), desc: Tr.t("Taskbar with Start menu style"), preset: "windows" },
        { name: Tr.t("macOS"), desc: Tr.t("Dock at bottom, clean layout"), preset: "macos" },
        { name: Tr.t("Ubuntu"), desc: Tr.t("Ubuntu-style with dock"), preset: "ubuntu" },
        { name: Tr.t("Unity"), desc: Tr.t("Unity launcher and dock"), preset: "unity" },
        { name: Tr.t("GNOME"), desc: Tr.t("Minimal dock, top bar focused"), preset: "gnome" },
        { name: Tr.t("Elementary"), desc: Tr.t("Clean elegant layout"), preset: "elementary" },
        { name: Tr.t("ChromeOS"), desc: Tr.t("Shelf at bottom"), preset: "chromeos" },
        { name: Tr.t("Tiling"), desc: Tr.t("Window tiling, no dock"), preset: "tiling" }
    ]

    onVisibleChanged: {
        if (visible && Settings.loaded) {
            previousPreset = Settings.data.layoutPreset || "default";
            currentPreset = previousPreset;
        }
    }

    function applyPreset(preset) {
        const p = preset || currentPreset || "default";
        currentPreset = p;
        Settings.data.layoutPreset = p;
        if (p === "default") {
            Settings.data.desktopWidgets = ["clock"];
            Settings.data.dock = true;
            Settings.data.dockAutoHide = false;
            return;
        }
        const widgets = {
            "windows": ["clock", "media", "weather", "stats"],
            "windows11": ["clock", "media", "weather", "stats"],
            "classic": ["clock", "media", "weather", "stats"],
            "macos": ["clock", "media"],
            "macos-like": ["clock", "media"],
            "ubuntu": ["clock"],
            "unity": ["clock"],
            "gnome": ["clock"],
            "elementary": ["clock", "media"],
            "pantheon": ["clock", "media"],
            "chromeos": ["clock"],
            "chromebook": ["clock"],
            "tiling": [],
            "i3": [],
            "dwm": []
        };
        Settings.data.desktopWidgets = widgets[p] !== undefined ? widgets[p] : ["clock"];

        const dockConfig = {
            "tiling": {dock: false, autoHide: true},
            "i3": {dock: false, autoHide: true},
            "dwm": {dock: false, autoHide: true},
            "unity": {dock: true, autoHide: true},
            "ubuntu": {dock: true, autoHide: true},
            "gnome": {dock: true, autoHide: true},
            "chromeos": {dock: true, autoHide: false},
            "chromebook": {dock: true, autoHide: false},
            "macos": {dock: true, autoHide: false},
            "macos-like": {dock: true, autoHide: false},
            "elementary": {dock: true, autoHide: false},
            "pantheon": {dock: true, autoHide: false},
            "windows": {dock: true, autoHide: false},
            "windows11": {dock: true, autoHide: false},
            "classic": {dock: true, autoHide: false}
        };
        const cfg = dockConfig[p] || {dock: true, autoHide: false};
        Settings.data.dock = cfg.dock;
        Settings.data.dockAutoHide = cfg.autoHide;
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
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Ui.layoutSwitcher = false;
                event.accepted = true;
            }
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
                    model: root.presets
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
                    onClicked: {
                        root.applyPreset(root.previousPreset);
                        Ui.layoutSwitcher = false;
                    }
                }
            }
        }
    }
}
