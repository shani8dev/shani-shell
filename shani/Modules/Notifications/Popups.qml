// New notifications, top right under the bar, newest at the top. Each leaves
// after its timeout (the app's, else 6 s; critical ones stay until handled) or
// on hover-out after being hovered. They stay in the sidebar's history.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens[0]
    visible: Notifs.popups.length > 0 && !Ui.controlCenter && !Ui.launcher && !Lock.locked
    anchors { top: true; right: true }
    margins { top: Theme.barHeight + 18; right: 12 }
    implicitWidth: 380
    implicitHeight: list.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.data.blur ? popRegion : null
    Region { id: popRegion; item: list }

    ColumnLayout {
        id: list
        width: parent.width
        spacing: 8
        Repeater {
            model: Notifs.popups.slice().reverse()
            NotificationCard {
                id: card
                required property var modelData
                Layout.fillWidth: true
                notification: modelData
                popup: true
                onDone: Notifs.dropPopup(modelData)
                HoverHandler { id: hover }
                Timer {
                    running: !card.critical && !hover.hovered
                    interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout * 1000 : 6000
                    onTriggered: Notifs.dropPopup(card.modelData)
                }
            }
        }
    }
}
