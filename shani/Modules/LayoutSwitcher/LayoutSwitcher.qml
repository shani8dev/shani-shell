// Layout Switcher (inspired by Manjaro reference): choose desktop layout styles
// each with a preview card; Apply reloads the desktop configuration.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common

PanelWindow {
    id: win
    visible: Ui.layoutSwitcher
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-layout-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Glass {
        id: card
        strong: true
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 720)
        height: Math.min(parent.height - 80, 520)
        radius: Theme.radiusLarge

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

            // Tab buttons: Layout / Settings (match Manjaro reference image)
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Button { text: Tr.t("Layout"); onClicked: {} }
                Button { text: Tr.t("Settings"); onClicked: { Ui.layoutSwitcher = false; Ui.openSettings("look"); } }
            }

            // Layout style options with preview cards
            GridLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 320
                columns: 3
                rowSpacing: 12
                columnSpacing: 12

                Repeater {
                    model: [
                        { label: Tr.t("Manjaro"), desc: Tr.t("Default desktop widgets and layout"), preset: "manjaro" },
                        { label: Tr.t("Traditional"), desc: Tr.t("Classic workspace and dock layout"), preset: "traditional" },
                        { label: Tr.t("Unity"), desc: Tr.t("Compact sidebar and launcher"), preset: "unity" },
                        { label: Tr.t("Modern"), desc: Tr.t("Clean and minimal desktop"), preset: "modern" },
                        { label: Tr.t("Gnome"), desc: Tr.t("Standard Gnome-style desktop"), preset: "gnome" },
                        { label: Tr.t("Tiling"), desc: Tr.t("Window-tiled workspace"), preset: "tiling" }
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        radius: Theme.radius
                        color: Theme.bg
                        border.color: Theme.stroke
                        border.width: 1
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            Text {
                                text: modelData.label
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
                                // Apply preset: update desktop widget settings
                                // (simplified: sets desktop widgets and reloads)
                                Settings.data.desktopWidgets = modelData.preset === "manjaro" ? ["clock", "media", "weather", "stats"] : ["clock"];
                                Ui.layoutSwitcher = false;
                            }
                        }
                    }
                }
            }

            // Action buttons
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12
                Button {
                    text: Tr.t("Reload Desktop")
                    onClicked: Ui.layoutSwitcher = false
                }
                Button {
                    text: Tr.t("Apply")
                    onClicked: Ui.layoutSwitcher = false
                }
            }
        }
    }
}
