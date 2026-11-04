// A first-days hint on an empty workspace: the three keys that reach
// everything - apps, every window, quick settings - quietly in the middle of
// the wallpaper (the layer just above it: any window covers it). It goes for
// good after the launcher has been opened five times, or at its ×.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    readonly property var here: Niri.workspaces.find(w => w.is_focused) || null
    readonly property bool empty: here !== null && !Object.values(Niri.windows).some(w => w.workspace_id === here.id)
    visible: Settings.loaded && empty && !Settings.data.startHintsDone && Settings.data.launcherOpens < 5 && !Ui.launcher && !Niri.overviewOpen
    implicitWidth: card.implicitWidth + 8
    implicitHeight: card.implicitHeight + 8
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-start-hints"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Glass {
        id: card
        anchors.centerIn: parent
        implicitWidth: col.implicitWidth + 48
        implicitHeight: col.implicitHeight + 36
        radius: 22
        Column {
            id: col
            anchors.centerIn: parent
            spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tr.t("Nothing open here")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 16 * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Repeater {
                model: [{ keys: "Super + Space", what: Tr.t("open an app, a file or a setting - just type") },
                        { keys: "Super + O", what: Tr.t("see every window and workspace") },
                        { keys: "Super + ,", what: Tr.t("Wi-Fi, sound, brightness and more") },
                        { keys: "Super + Shift + /", what: Tr.t("every keyboard shortcut") }]
                Row {
                    required property var modelData
                    spacing: 12
                    Rectangle {
                        width: 132
                        height: 24
                        radius: 6
                        color: Theme.alpha(Theme.text, 0.09)
                        Text { anchors.centerIn: parent; text: parent.parent.modelData.keys; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.weight: Font.Medium }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.what; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
                }
            }
        }
        IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            icon: "window-close"
            size: 22
            tip: Tr.t("Don't show this again")
            onClicked: Settings.data.startHintsDone = true
        }
    }
}
