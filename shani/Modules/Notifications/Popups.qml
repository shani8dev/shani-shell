// New notifications, top right under the bar, newest at the top. Each leaves
// after its timeout (the app's, else 6 s; critical ones stay until handled) or
// with the time left paused while hovered. They stay in the sidebar's history.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    visible: Notifs.popups.length > 0 && !Ui.controlCenter && !Ui.launcher && !Lock.locked
        && Lens.phase !== "selecting" && Lens.phase !== "reading"   // not what Lens is pointed at
    // where pop-ups appear (Settings > Notifications); the dock keeps the bottom clear
    readonly property string pos: Settings.data.popupPosition
    anchors { top: pos !== "bottom-right"; bottom: pos === "bottom-right"; right: pos !== "top-center" }
    margins { top: Theme.barHeight + 18; right: 12; bottom: Settings.data.dock && !Settings.data.dockAutoHide ? Settings.data.dockIconSize + 44 : 16 }
    implicitWidth: 380
    implicitHeight: list.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.data.blur ? popRegion : null
    // rounded like the cards: a plain rectangle blurred a square box behind them
    Region { id: popRegion; item: list; radius: Theme.radiusLarge }

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
                // the time left runs down, paused while the pointer rests on it
                NumberAnimation on life {
                    running: !card.critical
                    paused: running && hover.hovered
                    from: 1
                    to: 0
                    duration: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout * 1000 : Settings.data.popupSeconds * 1000
                    onFinished: Notifs.dropPopup(card.modelData)
                }
            }
        }
    }
}
