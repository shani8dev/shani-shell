// The share sheet (Share): where a file can go, one click each.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    visible: Share.file !== "" && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-share"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // nothing preselected: a stray Enter must not share over the network
    property int sel: -1
    onVisibleChanged: sel = -1
    MouseArea { objectName: "nav:pointer"; anchors.fill: parent; onClicked: Share.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Share.close()
        Keys.onDownPressed: win.sel = Math.min(win.sel + 1, Share.targets.length - 1)
        Keys.onUpPressed: win.sel = Math.max(win.sel - 1, 0)
        Keys.onReturnPressed: if (win.sel >= 0) Share.choose(win.sel)
    }
    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Theme.px(380)
        implicitHeight: col.implicitHeight + 32
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }       // clicks inside do not close it
        // an on-screen exit: Escape and click-outside are not discoverable,
        // especially on touch
        IconButton {
            anchors { top: parent.top; right: parent.right; margins: Theme.px(10) }
            icon: "window-close"
            size: Theme.px(22)
            tip: Tr.t("Cancel")
            Accessible.name: Tr.t("Cancel")
            onClicked: Share.close()
        }
        ColumnLayout {
            id: col
            x: 16
            y: 16
            width: parent.width - 32
            spacing: Theme.px(4)
            Text {
                Layout.fillWidth: true
                text: Tr.t("Share %1").arg(Share.name)
                color: Theme.text
                elide: Text.ElideMiddle
                font.family: Theme.font
                font.pixelSize: Theme.px(15) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Item { implicitHeight: Theme.px(4) }
            Repeater {
                model: Share.targets
                ListRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.label
                    selected: index === win.sel
                    onClicked: Share.choose(index)
                }
            }
        }
    }
}
