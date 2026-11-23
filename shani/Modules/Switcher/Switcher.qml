// Alt+Tab: every window, most recently used first, the previous one already
// selected — so a quick Alt+Tab flips between the last two. Windows from one
// app fold into one tile (a count badge); G toggles back to the flat list, and
// Shift+Q closes every window of the selected app. Tab / Shift+Tab / arrows
// move, releasing Alt switches (the shell holds the keyboard while open, so it
// sees the release), Escape cancels, Q closes the selected window.
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
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    visible: Ui.switcher
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (Ui.switcher) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Ui.switcher && Settings.blurWanted ? swRegion : null
    Region { id: swRegion; item: card; radius: Theme.radiusLarge }

    property var list: []            // flat MRU, the source of truth for focus and closing
    property int sel: 0
    property bool grouped: true      // G toggles between per-app stacks and single windows

    function appKey(w) { return String((w && w.app_id) || "").toLowerCase() || "other"; }
    function buildGroups() {
        const out = [], byKey = {};
        for (const w of list) {
            const key = win.appKey(w);
            if (!byKey[key]) {
                byKey[key] = { key: key, windows: [] };
                out.push(byKey[key]);
            }
            byKey[key].windows.push(w);
        }
        return out;
    }
    readonly property var groups: win.buildGroups()
    function count() { return grouped ? groups.length : list.length; }
    function clampSel() { sel = Math.max(0, Math.min(sel, win.count() - 1)); }
    // the windows the current tile stands for: one, or a whole stack
    function currentWindows() {
        if (!grouped) {
            const w = list[sel];
            return w ? [w] : [];
        }
        const g = groups[sel];
        return g ? g.windows.slice() : [];
    }
    // every window of the selected app, flat view included (Shift+Q)
    function appWindows() {
        if (grouped)
            return win.currentWindows();
        const w = list[sel];
        if (!w)
            return [];
        const key = win.appKey(w);
        return list.filter(x => win.appKey(x) === key);
    }

    function open(back) {
        // the hidden "minimised" workspace is not part of the switcher (the dock hides it too)
        list = Niri.mru().filter(w => !Niri.isMinimised(w));
        // One app on screen has one tile, and Alt+Tab with one tile goes
        // nowhere: the tiles are its windows instead, so two terminals still
        // swap. The G toggle stays as it was for a real mix of apps.
        if (win.buildGroups().length <= 1)
            grouped = false;
        sel = list.length > 1 ? (back ? list.length - 1 : 1) : 0;
        win.clampSel();
        Ui.switcher = true;
        keys.forceActiveFocus();
    }
    function step(d) {
        const n = win.count();
        if (n > 0)
            sel = (sel + d + n) % n;
    }
    function commit() {
        const ws = win.currentWindows();
        Ui.switcher = false;
        if (ws.length)
            Niri.focusWin(ws[0]);
    }
    function close(w) {
        if (!w)
            return;
        Niri.action("close-window", "--id", w.id);
        win.list = win.list.filter(x => x !== w);
        win.clampSel();
    }
    function closeApp() {
        const ws = win.appWindows();
        if (!ws.length)
            return;
        for (const w of ws)
            Niri.action("close-window", "--id", w.id);
        win.list = win.list.filter(x => ws.indexOf(x) < 0);
        win.clampSel();
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
            else if (e.key === Qt.Key_G && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                win.grouped = !win.grouped;
                win.clampSel();
            } else if (e.key === Qt.Key_Q && (e.modifiers & Qt.ShiftModifier))
                win.closeApp();
            else if (e.key === Qt.Key_Q)
                win.close(win.currentWindows()[0]);
            e.accepted = true;
        }
        Keys.onReleased: e => {
            // Escape / a background click cancels: a later modifier release must not switch
            if (Ui.switcher && (e.key === Qt.Key_Alt || e.key === Qt.Key_Super_L || e.key === Qt.Key_Meta))
                win.commit();
        }
    }

    MouseArea { objectName: "nav:pointer"; anchors.fill: parent; onClicked: Ui.switcher = false }

    Glass {
        id: card
        strong: true
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, Math.max(320, row.implicitWidth + 32))
        height: Theme.px(200)
        radius: Theme.radiusLarge

        Text {
            visible: win.count() === 0
            anchors.centerIn: parent
            text: Tr.t("No windows open")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(13) * Theme.fontScale
        }

        ListView {
            reuseItems: true
            cacheBuffer: 400
            id: row
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            anchors.bottomMargin: Theme.px(40)
            orientation: ListView.Horizontal
            spacing: Theme.px(10)
            clip: true
            model: win.grouped ? win.groups : win.list
            currentIndex: win.sel
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            implicitWidth: win.count() * 130
            delegate: Rectangle {
                id: cell
                required property var modelData
                required property int index
                // a group is { key, windows }; a flat row is a window
                readonly property bool isGroup: win.grouped
                readonly property string appId: isGroup ? (cell.modelData.key || "") : (cell.modelData.app_id || "")
                readonly property var entry: DesktopEntries.heuristicLookup(cell.appId)
                readonly property int windowCount: isGroup ? cell.modelData.windows.length : 1
                readonly property string title: isGroup
                    ? (cell.entry ? cell.entry.name : cell.appId)
                    : (cell.modelData.title || cell.appId)
                width: Theme.px(120)
                height: Theme.px(144)
                radius: Theme.px(16)
                color: index === win.sel ? Theme.accentSoft : (cellArea.containsMouse ? Theme.hover : "transparent")
                border.width: index === win.sel ? 2 : 0
                border.color: Theme.accentLine
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(10)
                    spacing: Theme.px(6)
                    AppIcon {
                        Layout.alignment: Qt.AlignHCenter
                        implicitSize: 56
                        icon: cell.entry ? cell.entry.icon : cell.appId
                        name: cell.title
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.title
                        color: Theme.text
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.isGroup ? Tr.t("%1 windows", cell.windowCount)
                                           : Niri.workspaceLabel(cell.modelData.workspace_id)
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.px(10) * Theme.fontScale
                    }
                }
                // a stack carries a count badge, so it never silently hides windows
                Rectangle {
                    visible: cell.isGroup && cell.windowCount > 1
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.px(6)
                    implicitWidth: Math.max(Theme.px(20), badgeText.implicitWidth + Theme.px(10))
                    implicitHeight: Theme.px(20)
                    radius: Theme.px(10)
                    color: Theme.accent
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: cell.windowCount
                        color: Theme.accentInk
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    id: cellArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: win.sel = cell.index
                    onClicked: win.commit()
                }
                Accessible.role: Accessible.Button
                Accessible.name: cell.title + (cell.isGroup && cell.windowCount > 1 ? ", " + Tr.t("%1 windows", cell.windowCount) : "")
                KeyFocus {
                    name: cell.Accessible.name
                    onActivated: win.commit()
                }
            }
        }

        Text {
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.px(8) }
            text: Tr.t("Tab move · Enter switch · Esc cancel · G group · Q close · Shift+Q close app")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
    }
}
