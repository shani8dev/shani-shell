// The share sheet (Share): where a file can go, one click each.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    visible: Share.files.length > 0 && !Lock.locked
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
    Accessible.name: Tr.t("Share %1").arg(Share.name)

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
        Keys.onEnterPressed: if (win.sel >= 0) Share.choose(win.sel)   // keypad Enter is Key_Enter, not Key_Return
        // Up/Down walk one at a time; Home/End jump to the first or last target
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Home) win.sel = 0
            else if (e.key === Qt.Key_End) win.sel = Share.targets.length - 1
            else return
            e.accepted = true
        }
    }
    // ---- a failed target (the last command answered false) -----------------
    Text {
        visible: Share.lastError !== ""
        anchors { horizontalCenter: parent.horizontalCenter; top: win.top; margins: Theme.px(10) }
        text: Share.lastError
        color: Theme.danger
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
        Accessible.name: text
    }
    // ---- drop files onto the sheet -----------------------------------------
    DropArea {
        id: dropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        // DropArea is a QtObject: an Accessible attached property needs an Item
        property string accessibleName: Tr.t("Drop files onto the sheet")
        onEntered: drag => { if (!drag.hasUrls) drag.accepted = false; }
        onDropped: drop => {
            if (!drop.hasUrls)
                return;
            Share.open(drop.urls.map(u => u.toLocalFile()).filter(p => p !== ""));
            drop.accept();
        }
    }
    Glass {
        id: blurCard
        anchors.centerIn: parent
        width: Theme.px(380)
        implicitHeight: Math.min(col.implicitHeight + 32, parent.height - 80)
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
            onClicked: Share.cancel()
        }
        // "Archive and share (zip)": the sheet stays open while the archive is made
        Timer {
            id: archiveTimer
            interval: 400
            running: Share.archiveWait
            onTriggered: Share.archiveChanged()
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
                Accessible.name: text
                color: Theme.text
                elide: Text.ElideMiddle
                font.family: Theme.font
                font.pixelSize: Theme.px(15) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Item { implicitHeight: Theme.px(4) }
            // the sheet is empty only when there is nothing to share it to
            EmptyState {
                id: empty
                visible: Share.targets.length === 0
                icon: "folder-publicshare"
                title: Tr.t("No targets yet")
                subtitle: Tr.t("Turn on Phone or Bluetooth to see targets here")
            }
            Flickable {
                id: targetFlick
                visible: Share.targets.length > 0
                Layout.fillWidth: true
                // the card is capped above; many Bluetooth targets now scroll
                implicitHeight: Math.min(targetsCol.implicitHeight, win.height - 160)
                contentWidth: width
                contentHeight: targetsCol.implicitHeight
                clip: true
                ColumnLayout {
                    id: targetsCol
                    width: targetFlick.width
                    spacing: Theme.px(4)
                    Repeater {
                        model: Share.targets
                        ListRow {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            icon: Share.iconFor(modelData.icon)
                            title: modelData.label
                            subtitle: modelData.subtitle && modelData.subtitle !== "" ? modelData.subtitle : Share.targetStateText(modelData.state)
                            Accessible.name: modelData.recent ? Tr.t("Recent: %1").arg(modelData.label) : modelData.label
                            selected: index === win.sel
                            onClicked: Share.choose(index)
                        }
                    }
                }
            }
        }
    }
}
