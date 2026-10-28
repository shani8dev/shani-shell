// The dock, after Latte: pinned apps then whatever else is running, with
// parabolic zoom — the icon under the pointer and its neighbours swell along a
// smooth curve and grow upward — a bounce when an app is launched, and glowing
// indicators counting its windows (niri's event stream). Click focuses the
// app (again: the next window) or launches it; middle-click opens a new one;
// right-click pins or unpins. With auto-hide it waits below the edge and rises
// when the pointer touches the bottom.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens[0]
    visible: Settings.data.dock && !Lock.locked
    anchors.bottom: true
    // sized for the widest zoom once, so the surface is not resized on every pointer move
    implicitWidth: items.length * (base + 4) + (peak - base) * 3 + 80
    implicitHeight: 140                 // room for a zoomed icon and its label
    color: "transparent"
    exclusionMode: Settings.data.dockAutoHide ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: Settings.data.dockAutoHide ? 0 : 76
    WlrLayershell.namespace: "shani-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.data.blur && shown ? dockRegion : null
    Region { id: dockRegion; item: dock; radius: dock.radius }

    readonly property bool shown: !Settings.data.dockAutoHide || hover.hovered
    // when hidden only a 4 px strip at the bottom edge takes input
    mask: Region { item: win.shown ? zone : edge }

    readonly property var entryOf: id => DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id)
    readonly property var running: {
        const groups = {};
        for (const w of Object.values(Niri.windows)) {
            const key = (w.app_id || "").toLowerCase();
            (groups[key] = groups[key] || []).push(w);
        }
        return groups;
    }
    readonly property var items: {
        const out = [], seen = {};
        for (const id of Settings.data.dockPinned) {
            const e = win.entryOf(id);
            if (!e)
                continue;
            const key = (e.startupClass || e.id).toLowerCase();
            const ws = win.running[key] || win.running[e.id.toLowerCase()] || [];
            seen[key] = seen[e.id.toLowerCase()] = true;
            out.push({ id: e.id, entry: e, windows: ws, pinned: true });
        }
        for (const key of Object.keys(win.running)) {
            if (seen[key] || key === "")
                continue;
            out.push({ id: key, entry: win.entryOf(key), windows: win.running[key], pinned: false });
        }
        return out;
    }

    // parabolic zoom: base 44 px, up to 72 px right under the pointer,
    // falling off over about two icons either side
    readonly property real base: 44
    readonly property real peak: 72
    property real pointerX: -1000
    function sizeAt(centerX) {
        if (!hover.hovered)
            return base;
        const d = (centerX - pointerX) / (base * 1.6);
        return base + (peak - base) * Math.exp(-d * d);
    }

    signal launched(string id)

    function activate(it) {
        if (it.windows.length === 0) {
            if (it.entry) {
                it.entry.execute();
                launched(it.id);
            }
            return;
        }
        const ids = it.windows.map(w => w.id).sort((a, b) => a - b);
        const cur = ids.indexOf(Niri.focusedWindowId);
        Niri.action("focus-window", "--id", ids[cur < 0 ? 0 : (cur + 1) % ids.length]);
    }
    function togglePin(it) {
        const list = Array.from(Settings.data.dockPinned);
        const i = list.indexOf(it.entry ? it.entry.id : it.id);
        if (i >= 0)
            list.splice(i, 1);
        else if (it.entry)
            list.push(it.entry.id);
        Settings.data.dockPinned = list;
    }

    HoverHandler { id: hover }

    // input: the base plus the space a zoomed icon rises into
    Item {
        id: zone
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: dock.width
        height: win.peak + 60
    }
    Item {
        id: edge
        anchors.bottom: parent.bottom
        width: parent.width
        height: 4
    }

    // the slim base the icons stand on; it never zooms, the icons rise above it
    Glass {
        id: dock
        strong: true
        width: row.width + 24
        height: win.base + 18
        radius: 18
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.shown ? parent.height - height - 10 : parent.height + 4
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 90 } }
    }

    MouseArea {
        anchors.fill: row
        anchors.topMargin: -30
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: m => win.pointerX = mapToItem(row, m.x, m.y).x
        onExited: win.pointerX = -1000
    }

    Row {
        id: row
        anchors.horizontalCenter: dock.horizontalCenter
        anchors.bottom: dock.bottom
        anchors.bottomMargin: 9
        spacing: 4

        Repeater {
            model: win.items
            Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool focused: modelData.windows.some(w => w.id === Niri.focusedWindowId)
                // the cell's centre in the row, at base size (stable, so the curve does not chase itself)
                readonly property real restCenter: index * (win.base + row.spacing) + win.base / 2
                readonly property real size: win.sizeAt(restCenter)
                width: size
                height: size
                Behavior on width { NumberAnimation { duration: 70 } }

                IconImage {
                    id: icon
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    implicitSize: cell.size
                    source: Quickshell.iconPath(cell.modelData.entry ? cell.modelData.entry.icon : cell.modelData.id, "application-x-executable")

                    // launch bounce
                    transform: Translate { id: lift; y: 0 }
                    SequentialAnimation {
                        id: bounce
                        loops: 2
                        NumberAnimation { target: lift; property: "y"; to: -18; duration: 220; easing.type: Easing.OutQuad }
                        NumberAnimation { target: lift; property: "y"; to: 0; duration: 260; easing.type: Easing.OutBounce }
                    }
                }
                Connections {
                    target: win
                    function onLaunched(id) {
                        if (id === cell.modelData.id)
                            bounce.restart();
                    }
                }

                // Latte-style indicators: glowing pips, a bar for the focused app
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 2
                    spacing: 3
                    Repeater {
                        model: Math.min(3, cell.modelData.windows.length)
                        Rectangle {
                            width: cell.focused ? 14 : 5
                            height: 4
                            radius: 2
                            color: cell.focused ? Theme.accent : Theme.dim
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + 6
                                height: parent.height + 6
                                radius: height / 2
                                color: Theme.alpha(parent.color, 0.25)
                                z: -1
                            }
                        }
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: e => {
                        if (e.button === Qt.RightButton)
                            win.togglePin(cell.modelData);
                        else if (e.button === Qt.MiddleButton && cell.modelData.entry) {
                            cell.modelData.entry.execute();
                            bounce.restart();
                        } else
                            win.activate(cell.modelData);
                    }
                }
                ToolTipText {
                    visible: area.containsMouse
                    text: cell.modelData.entry ? cell.modelData.entry.name : cell.modelData.id
                }
            }
        }
    }

    component ToolTipText: Glass {
        property alias text: tip.text
        strong: true
        width: tip.implicitWidth + 16
        height: 24
        radius: 8
        anchors.horizontalCenter: parent.horizontalCenter
        y: -32
        Text {
            id: tip
            anchors.centerIn: parent
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 11
        }
    }
}
