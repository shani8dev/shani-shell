import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Keyboard shortcuts") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Text { Layout.fillWidth: true; text: Tr.t("Shell"); color: Theme.accent; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.weight: 600 }
        Repeater {
            model: [
                {k: "Mod+Space", d: "Launcher"},
                {k: "Mod+Shift+Space", d: "Toggle top bar"},
                {k: "Mod+X", d: "Ring (pie menu)"},
                {k: "Alt+Tab", d: "Window switcher"},
                {k: "Mod+Period", d: "Settings"},
                {k: "Mod+M", d: "Plugins/settings"},
                {k: "Mod+Shift+S", d: "Screenshot area"},
                {k: "Print", d: "Screenshot"},
                {k: "Mod+Ctrl+V", d: "Clipboard history"},
                {k: "Mod+Ctrl+Y", d: "Chronoa/Agent panel"}
            ]
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text { text: modelData.k; color: Theme.text; font.family: Theme.monoFont || Theme.font; font.pixelSize: 11 * Theme.fontScale; Layout.preferredWidth: 160 }
                Text { text: modelData.d; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale; Layout.fillWidth: true }
            }
        }

        Text { Layout.fillWidth: true; text: Tr.t("Window management"); color: Theme.accent; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.weight: 600; Layout.topMargin: 8 }
        Repeater {
            model: [
                {k: "Mod+Q", d: "Close window"},
                {k: "Mod+F", d: "Fullscreen"},
                {k: "Mod+V", d: "Toggle float"},
                {k: "Mod+H/J/K/L", d: "Focus window"},
                {k: "Mod+Shift+H/J/K/L", d: "Move window"},
                {k: "Mod+1..9", d: "Switch workspace"},
                {k: "Mod+Shift+1..9", d: "Move to workspace"}
            ]
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text { text: modelData.k; color: Theme.text; font.family: Theme.monoFont || Theme.font; font.pixelSize: 11 * Theme.fontScale; Layout.preferredWidth: 160 }
                Text { text: modelData.d; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.fontScale; Layout.fillWidth: true }
            }
        }
    }
}
