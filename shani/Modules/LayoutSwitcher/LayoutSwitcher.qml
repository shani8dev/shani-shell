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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 720)
        height: Math.min(parent.height - 80, 520)
        radius: Theme.radiusLarge
        strong: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: "Layout Switcher"
                font.family: Theme.font
                font.pixelSize: 18 * Theme.fontScale
                font.weight: Font.Bold
                color: Theme.text
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Button { text: "Layout"; onClicked: {} }
                Button { text: "Settings"; onClicked: { Ui.layoutSwitcher = false; Ui.openSettings("look"); } }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 300
                columns: 3
                rowSpacing: 12
                columnSpacing: 12
                Repeater {
                    model: [
                        { name: "Manjaro", desc: "Default desktop widgets and layout", preset: "manjaro" },
                        { name: "Traditional", desc: "Classic workspace and dock layout", preset: "traditional" },
                        { name: "Unity", desc: "Compact sidebar and launcher", preset: "unity" },
                        { name: "Modern", desc: "Clean and minimal desktop", preset: "modern" },
                        { name: "Gnome", desc: "Standard Gnome-style desktop", preset: "gnome" },
                        { name: "Tiling", desc: "Window-tiled workspace", preset: "tiling" }
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 100
                        radius: Theme.radius
                        color: Theme.bg
                        border.color: Theme.stroke
                        border.width: 1
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
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Settings.data.desktopWidgets = modelData.preset === "manjaro"
                                    ? ["clock", "media", "weather", "stats"]
                                    : ["clock"];
                                // Dock/panel changes per preset
                                Settings.data.dock = modelData.preset !== "tiling";
                                Settings.data.dockAutoHide = modelData.preset === "tiling" || modelData.preset === "unity";
                                Ui.layoutSwitcher = false;
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12
                Button {
                    text: "Reload Desktop"
                    onClicked: Ui.layoutSwitcher = false
                }
                Button {
                    text: "Apply"
                    onClicked: Ui.layoutSwitcher = false
                }
            }
        }
    }
}
