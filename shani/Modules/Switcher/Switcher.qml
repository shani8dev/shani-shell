// Alt+Tab: every window, most recently used first, the previous one already
// selected — so a quick Alt+Tab flips between the last two. Tab / Shift+Tab /
// arrows move, releasing Alt switches (the shell holds the keyboard while
// open, so it sees the release), Escape cancels, Q closes the selected window.
// niri has no per-window capture protocol, so these are icons and titles,
// not live thumbnails.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.switcher
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Ui.switcher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Ui.switcher && Settings.data.blur ? swRegion : null
    Region { id: swRegion; item: card; radius: Theme.radiusLarge }

    property var list: []
    property int sel: 0

    function open(back) {
        list = Niri.mru();
        sel = list.length > 1 ? (back ? list.length - 1 : 1) : 0;
        Ui.switcher = true;
        keys.forceActiveFocus();
    }
    function step(d) {
        if (list.length > 0)
            sel = (sel + d + list.length) % list.length;
    }
    function commit() {
        const w = list[sel];
        Ui.switcher = false;
        if (w)
            Niri.action("focus-window", "--id", w.id);
    }

    Connections {
        target: Ui
        function onSwitcherRequested(back) {
            if (Ui.switcher)
                win.step(back ? -1 : 1);
            else
                win.open(back);
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right || e.key === Qt.Key_Down)
                win.step(1);
            else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left || e.key === Qt.Key_Up)
                win.step(-1);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                win.commit();
            else if (e.key === Qt.Key_Escape)
                Ui.switcher = false;
            else if (e.key === Qt.Key_Q && win.list[win.sel]) {
                Niri.action("close-window", "--id", win.list[win.sel].id);
                win.list = win.list.filter((_, i) => i !== win.sel);
                win.sel = Math.min(win.sel, win.list.length - 1);
            }
            e.accepted = true;
        }
        Keys.onReleased: e => {
            if (e.key === Qt.Key_Alt || e.key === Qt.Key_Super_L || e.key === Qt.Key_Meta)
                win.commit();
        }
    }

    MouseArea { anchors.fill: parent; onClicked: Ui.switcher = false }

    Glass {
        id: card
        strong: true
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, Math.max(320, row.implicitWidth + 32))
        height: 176
        radius: Theme.radiusLarge

        Text {
            visible: win.list.length === 0
            anchors.centerIn: parent
            text: Tr.t("No windows open")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 13 * Theme.fontScale
        }

        ListView {
            id: row
            anchors.fill: parent
            anchors.margins: 16
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            model: win.list
            currentIndex: win.sel
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            implicitWidth: win.list.length * 130
            delegate: Rectangle {
                id: cell
                required property var modelData
                required property int index
                width: 120
                height: 144
                radius: 16
                color: index === win.sel ? Theme.accentSoft : (cellArea.containsMouse ? Theme.hover : "transparent")
                border.width: index === win.sel ? 1 : 0
                border.color: Theme.accentLine
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        implicitSize: 56
                        source: {
                            const e = DesktopEntries.heuristicLookup(cell.modelData.app_id || "");
                            return Quickshell.iconPath(e ? e.icon : (cell.modelData.app_id || ""), "application-x-executable");
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.modelData.title || cell.modelData.app_id
                        color: Theme.text
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Niri.workspaceLabel(cell.modelData.workspace_id)
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                    }
                }
                MouseArea {
                    id: cellArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: win.sel = cell.index
                    onClicked: win.commit()
                }
            }
        }
    }
}
