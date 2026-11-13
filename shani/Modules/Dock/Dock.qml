// The dock, after Latte: pinned apps then whatever else is running, with
// parabolic zoom — the icon under the pointer and its neighbours swell along a
// smooth curve and grow upward — a bounce when an app is launched, and glowing
// indicators counting its windows (niri's event stream). Click focuses the
// app (again: the next window) or launches it; middle-click opens a new one;
// right-click pins or unpins. It stays (always), steps out of a window's way
// (smart: Services/Hiding) or waits below the edge (hide); hidden, it rises when
// the pointer rests against the bottom.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import Qt.labs.folderlistmodel
import qs.Common
import qs.Services

PanelWindow {
    id: win
    required property var modelData     // its screen: a dock on each
    screen: modelData
    visible: Settings.data.dock && !Lock.locked
    anchors.bottom: true
    // the screen's width: never resized on a pointer move, and never narrower than
    // the base. A width counted from the items once fell behind as the dock grew
    // (multitasking, show desktop, workspaces, the trash): the base outgrew its
    // surface and its rounded ends were cut off square. Input stays the dock's
    // own (mask: zone), so the transparent rest takes no clicks.
    implicitWidth: screen ? screen.width : 1920
    // room for a zoomed icon and its label (140 at 44 px), and the menu above it while open
    implicitHeight: peak + 68 + (menuFor >= 0 ? Math.max(230, menuHeight + 40) : 0)
    color: "transparent"
    readonly property string mode: Settings.data.dockVisibility
    // always and smart keep their space (windows never tile under the dock); hide gives the windows the whole height
    exclusionMode: mode === "hide" ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: mode === "hide" ? 0 : base + 32
    WlrLayershell.namespace: "shani-dock"
    WlrLayershell.layer: WlrLayer.Top
    // the keyboard reaches the dock on request (Ui.dockFocus: IPC focusDock, a controller):
    // it takes the keyboard until Escape, never otherwise
    WlrLayershell.keyboardFocus: Ui.dockFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && shown ? dockRegion : null
    Region { id: dockRegion; item: dock; radius: dock.radius }

    readonly property bool covered: mode === "smart" && Hiding.covered(output, "bottom", base + 32 + 2, screen ? screen.height : 1080,
        ((screen ? screen.width : 1920) - dock.width) / 2, ((screen ? screen.width : 1920) + dock.width) / 2)
    readonly property bool shown: mode === "always" || (revealed && hover.hovered) || menuFor >= 0 || dragging || Ui.dockFocus
        || Niri.overviewOpen || (mode === "smart" && (!covered || Hiding.urgent))
    Component.onCompleted: { Hiding.setDockShown(output, shown); Hiding.setDockFits(output, baseFits); }
    // the base fits its surface (the tests read it: a base wider than the surface
    // had its rounded ends cut off square)
    readonly property bool baseFits: dock.width <= width
    onBaseFitsChanged: Hiding.setDockFits(output, baseFits)
    property bool dragging: false        // a file carried to the bottom edge brings the dock up to drop on
    // the first time a smart dock steps aside, say where it went - once
    onShownChanged: {
        Hiding.setDockShown(output, shown);
        if (!shown && mode === "smart" && Settings.loaded && !Settings.data.dockHintSeen && modelData === Quickshell.screens[0])
            showHint();
    }
    function showHint() {
        Settings.data.dockHintSeen = true;     // (a floating window over it: the first time it steps aside)
        hintTimer.restart();
    }
    Timer { id: hintTimer; interval: 8000 }
    // pressure reveal (Pantheon, macOS): a hidden dock comes up after the pointer
    // rests against the bottom edge a moment, not as it passes on its way to a
    // window's bottom edge or a scrollbar
    property bool revealed: false
    Connections { target: hover; function onHoveredChanged() { if (!hover.hovered) win.revealed = false; } }
    Timer { interval: 250; running: edgeHover.hovered && !win.revealed; onTriggered: win.revealed = true }
    property int menuFor: -1            // the cell whose right-click menu is open
    property real menuHeight: 0         // the open menu's, which grows with an app's windows and actions
    // `qs ipc call shell dockMenu <app>` opens an app's menu as a right-click would (the tests)
    Connections {
        target: Ui
        function onDockMenuChanged() { win.menuFor = Ui.dockMenu ? win.items.findIndex(x => x.id === Ui.dockMenu || (x.entry && x.entry.id === Ui.dockMenu)) : -1; }
    }
    // when hidden only a 4 px strip at the bottom edge takes input
    mask: Region { item: win.menuFor >= 0 ? whole : win.shown ? zone : edge }

    // this screen's workspaces, for the dock's switcher (Pantheon's): the ones in
    // use or shown; niri keeps one empty at the end, which "+" goes to
    readonly property string output: screen ? screen.name : Niri.focusedOutput
    readonly property var allSpaces: Niri.workspacesOn(output)
    readonly property var spaces: allSpaces.filter(w => w.is_active || Object.values(Niri.windows).some(x => x.workspace_id === w.id))
    function windowsOn(ws) { return Object.values(Niri.windows).filter(x => x.workspace_id === ws.id); }
    function newWorkspace() {
        const last = allSpaces[allSpaces.length - 1];
        if (last && windowsOn(last).length === 0)
            Niri.focusWorkspace(last);
        else if (last)
            Niri.action("focus-workspace", last.idx + 1);
    }
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
            if (!e || !AppFilter.allowed(e.id))
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

    // parabolic zoom: base (44 px by default) up to about 1.6× right under the
    // pointer, falling off over about two icons either side
    readonly property real base: Settings.data.dockIconSize
    readonly property real peak: Math.round(base * 1.64)
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
                Launch.app(it.entry.id);
                launched(it.id);
            }
            return;
        }
        // an app whose windows are all minimised: the dock brings them back
        const down = it.windows.filter(w => Niri.isMinimised(w));
        if (down.length === it.windows.length) {
            down.forEach(w => Niri.restore(w.id));
            return;
        }
        const ids = it.windows.filter(w => !Niri.isMinimised(w)).map(w => w.id).sort((a, b) => a - b);
        const cur = ids.indexOf(Niri.focusedWindowId);
        Niri.action("focus-window", "--id", ids[cur < 0 ? 0 : (cur + 1) % ids.length]);
    }
    // move a pinned app one place along the pinned list
    function movePin(it, by) {
        const list = Array.from(Settings.data.dockPinned);
        const i = list.indexOf(it.entry ? it.entry.id : it.id), j = i + by;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        list.splice(i, 1);
        list.splice(j, 0, it.entry ? it.entry.id : it.id);
        Settings.data.dockPinned = list;
    }
    function closeAll(it) {
        for (const w of it.windows)
            Niri.action("close-window", "--id", String(w.id));
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
    Item { id: whole; anchors.fill: parent }
    // a click anywhere else closes the menu
    MouseArea {
        anchors.fill: parent
        visible: win.menuFor >= 0
        onClicked: win.menuFor = -1
    }

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
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, dock.width + 120)   // under the dock, not the whole screen's edge
        height: 4
        HoverHandler { id: edgeHover }
        // a drag gives no hover: carrying a file to the edge raises the dock too
        DropArea { anchors.fill: parent; onEntered: { win.dragging = true; dragOff.restart(); } }
    }
    property int dropsIn: 0              // cells a drag is over now
    Timer { id: dragOff; interval: 2500; onTriggered: if (win.dropsIn <= 0) win.dragging = false; else restart() }

    // the slim base the icons stand on; it never zooms, the icons rise above it
    Glass {
        id: dock
        strong: true
        // even breathing room around the icons, at any size
        width: row.width + win.base * 0.5
        height: win.base * 1.42
        radius: height * 0.32
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

    Connections {
        target: Ui
        function onDockFocusChanged() { if (Ui.dockFocus) Ui.focusFirst(row); else win.menuFor = -1; }
    }
    Row {
        id: row
        focus: Ui.dockFocus
        // Escape: a menu first, then the dock gives the keyboard back
        Keys.onEscapePressed: { if (win.menuFor >= 0) win.menuFor = -1; else Ui.dockFocus = false; }
        anchors.horizontalCenter: dock.horizontalCenter
        anchors.bottom: dock.bottom
        anchors.bottomMargin: (dock.height - win.base) / 2
        spacing: Math.round(win.base * 0.18)

        // ---- the dock after Pantheon's (elementary OS 8): every item is an
        // app-sized square, so the row keeps one rhythm. First Multitasking View
        // and show the desktop; after the apps and a hairline, the workspaces -
        // each a square holding its apps, a 2x2 grid, the one shown tinted with
        // the accent (a click on it opens the overview) - and "+" for a new one.
        Row {
            id: controls
            spacing: row.spacing
            // Multitasking View (Pantheon's first item): every workspace and its windows
            DockTile {
                id: multi
                on: Niri.overviewOpen
                tip: Tr.t("Multitasking view")
                icon: "focus-windows"
                onActivated: Niri.action("toggle-overview")
                // two windows above a strip of workspaces, drawn as Pantheon's icon is
                Item {
                    anchors.centerIn: parent
                    width: parent.width * 0.56
                    height: width
                    readonly property color ink: multi.on ? Theme.accent : Theme.text
                    Rectangle { x: 0; y: 0; width: parent.width * 0.58; height: parent.height * 0.56; radius: 3; color: parent.ink; opacity: 0.9 }
                    Rectangle { x: parent.width * 0.66; y: 0; width: parent.width * 0.34; height: parent.height * 0.25; radius: 2; color: parent.ink; opacity: 0.9 }
                    Rectangle { x: parent.width * 0.66; y: parent.height * 0.31; width: parent.width * 0.34; height: parent.height * 0.25; radius: 2; color: parent.ink; opacity: 0.9 }
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: parent.width * 0.08
                        Repeater {
                            model: 3
                            Rectangle { width: parent.parent.width * 0.26; height: parent.parent.height * 0.26; radius: 2; color: "transparent"; border.width: 1.5; border.color: parent.parent.ink }
                        }
                    }
                }
            }
            DockTile {
                id: desk
                on: Niri.desktopShown.length > 0
                tip: Tr.t("Show the desktop")
                icon: "computer"
                onActivated: Niri.showDesktop()
                // a small screen with nothing on it (drawn: icon themes disagree on this one)
                Item {
                    anchors.centerIn: parent
                    width: parent.width * 0.5
                    height: width * 0.86
                    readonly property color ink: desk.on ? Theme.accent : Theme.text
                    Rectangle {
                        width: parent.width
                        height: parent.height * 0.72
                        radius: 4
                        color: "transparent"
                        border.width: 2
                        border.color: parent.ink
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: parent.width * 0.5
                        height: 2
                        radius: 1
                        color: parent.ink
                    }
                }
            }
        }
        // the two system buttons, then the apps: a hairline between, so each group reads as one
        DockSeparator {}

        Repeater {
            model: win.items
            Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool focused: modelData.windows.some(w => w.id === Niri.focusedWindowId)
                // the app's own count (LauncherEntry) when it gives one, else its notifications
                readonly property var launcherEntry: LauncherEntries.of(modelData.entry, modelData.id)
                readonly property int badge: launcherEntry && launcherEntry.countVisible ? launcherEntry.count : Notifs.countFor(modelData.entry, modelData.id)
                readonly property real progress: launcherEntry && launcherEntry.progressVisible ? Math.max(0, Math.min(1, launcherEntry.progress)) : -1
                Accessible.role: Accessible.Button
                Accessible.name: (modelData.entry ? modelData.entry.name : modelData.id)
                    + (badge ? ", " + (badge === 1 ? Tr.t("1 notification") : Tr.t("%1 notifications", badge)) : "")
                    + (progress >= 0 ? ", " + Tr.t("%1% done", Math.round(progress * 100)) : "")
                Accessible.onPressAction: win.activate(modelData)
                // the cell's centre in the row, at base size (stable, so the curve does not chase itself)
                readonly property real restCenter: controls.width + row.spacing + index * (win.base + row.spacing) + win.base / 2
                readonly property real size: win.sizeAt(restCenter)
                width: size
                height: size
                Behavior on width { NumberAnimation { duration: 70 } }

                AppIcon {
                    id: icon
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    implicitSize: cell.size
                    icon: cell.modelData.entry ? cell.modelData.entry.icon : cell.modelData.id
                    name: cell.modelData.entry ? cell.modelData.entry.name : cell.modelData.id

                    // launch bounce
                    transform: Translate { id: lift; y: 0 }
                    SequentialAnimation {
                        id: bounce
                        loops: 2
                        NumberAnimation { target: lift; property: "y"; to: -18; duration: 220; easing.type: Easing.OutQuad }
                        NumberAnimation { target: lift; property: "y"; to: 0; duration: 260; easing.type: Easing.OutBounce }
                    }
                }
                // a download's or a copy's progress, as the app reports it
                Rectangle {
                    visible: cell.progress >= 0
                    anchors.horizontalCenter: icon.horizontalCenter
                    anchors.bottom: icon.bottom
                    anchors.bottomMargin: 2
                    width: icon.width * 0.8
                    height: 5
                    radius: 2.5
                    color: Theme.alpha(Theme.bg, 0.8)
                    Rectangle {
                        width: parent.width * Math.max(0, cell.progress)
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.anim } }
                    }
                }
                // unread notifications (macOS's red badge, Android's dot)
                Rectangle {
                    visible: cell.badge > 0
                    anchors.right: icon.right
                    anchors.top: icon.top
                    anchors.topMargin: -2
                    anchors.rightMargin: -2
                    height: 18
                    width: Math.max(18, badgeText.implicitWidth + 10)
                    radius: 9
                    color: Theme.red
                    border.width: 1.5
                    border.color: Theme.bg
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: cell.badge > 99 ? "99+" : cell.badge
                        color: "white"
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                        font.weight: Font.DemiBold
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

                // files dragged onto an app open in it (Plank, the macOS dock, the taskbar)
                DropArea {
                    id: drop
                    anchors.fill: parent
                    onEntered: d => { win.dropsIn++; d.accept(d.hasUrls && cell.modelData.entry ? Qt.CopyAction : Qt.IgnoreAction); }
                    onExited: { win.dropsIn = Math.max(0, win.dropsIn - 1); dragOff.restart(); }
                    // held there: its windows come forward one by one, to drop into one of them
                    Timer {
                        interval: 700
                        repeat: true
                        running: drop.containsDrag && cell.modelData.windows.length > 0
                        onTriggered: win.activate(cell.modelData)
                    }
                    onDropped: d => {
                        win.dropsIn = 0; win.dragging = false;
                        if (!cell.modelData.entry)
                            return;
                        const files = d.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, "")));
                        Ui.openFilesWith(cell.modelData.entry.id, files);
                        bounce.restart();
                    }
                }
                Rectangle {
                    visible: drop.containsDrag
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 12
                    color: Theme.accentSoft
                    border.color: Theme.accent
                    z: -1
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onPressAndHold: win.menuFor = cell.index
                    onWheel: w => {
                        const ids = cell.modelData.windows.filter(x => !Niri.isMinimised(x)).map(x => x.id).sort((p, q) => p - q);
                        if (!ids.length)
                            return;
                        const cur = ids.indexOf(Niri.focusedWindowId), by = w.angleDelta.y < 0 ? 1 : -1;
                        Niri.focusWin(Niri.windows[ids[cur < 0 ? 0 : (cur + by + ids.length) % ids.length]]);
                    }
                    onClicked: e => {
                        if (e.button === Qt.RightButton)
                            win.menuFor = win.menuFor === cell.index ? -1 : cell.index;
                        else if (e.button === Qt.MiddleButton && cell.modelData.entry) {
                            Launch.app(cell.modelData.entry.id);
                            bounce.restart();
                        } else
                            win.activate(cell.modelData);
                    }
                }
                // keyboard and controller: Enter opens or focuses it, Menu (X) its menu
                KeyFocus {
                    name: cell.Accessible.name
                    radius: 12
                    onActivated: { win.activate(cell.modelData); Ui.dockFocus = false; }
                    onMenu: { win.menuFor = cell.index; Ui.focusFirst(menuBox); }
                }
                // the right-click menu: what can be done with this app
                Glass {
                    id: menuBox
                    visible: win.menuFor === cell.index
                    onHeightChanged: if (visible) win.menuHeight = height
                    onVisibleChanged: if (visible) win.menuHeight = height
                    strong: true
                    radius: 12
                    width: 190
                    height: menuCol.implicitHeight + 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 16
                    z: 10
                    Column {
                        id: menuCol
                        x: 6
                        y: 6
                        width: parent.width - 12
                        Repeater {
                            model: [
                                // its windows by title (the taskbar's window list), then the
                                // app's own actions (Plank's and Windows' jump list)
                                ...cell.modelData.windows.slice(0, 8).map(w => ({ label: (Niri.isMinimised(w) ? "▾ " : "") + ((Niri.windows[w.id] || w).title || cell.modelData.id), show: true, sep: false,
                                    run: () => Niri.focusWin(w) })),
                                ...(cell.modelData.entry ? Array.from(cell.modelData.entry.actions).slice(0, 6).map((act, i) => ({ label: act.name, show: true, sep: i === 0 && cell.modelData.windows.length > 0,
                                    run: () => { Launch.app(cell.modelData.entry.id, { action: act.id }); bounce.restart(); } })) : []),
                                { label: Tr.t("New window"), sep: true, show: !!cell.modelData.entry, run: () => { Launch.app(cell.modelData.entry.id); bounce.restart(); } },
                                { label: "Open on " + (Gpu.other ? Gpu.other.name.split(" ").slice(0, 3).join(" ") : "the other GPU"), show: !!cell.modelData.entry && Gpu.hasChoice,
                                  run: () => { Gpu.launchOnOther(cell.modelData.entry.id); bounce.restart(); } },
                                { label: cell.modelData.pinned ? "Unpin from dock" : "Pin to dock", show: !!cell.modelData.entry, run: () => win.togglePin(cell.modelData) },
                                { label: Tr.t("Move left"), show: cell.modelData.pinned && cell.index > 0, run: () => win.movePin(cell.modelData, -1) },
                                { label: Tr.t("Move right"), show: cell.modelData.pinned && cell.index < Settings.data.dockPinned.length - 1, run: () => win.movePin(cell.modelData, 1) },
                                { label: cell.modelData.windows.length > 1 ? "Close " + cell.modelData.windows.length + " windows" : "Close window", show: cell.modelData.windows.length > 0, run: () => win.closeAll(cell.modelData) }
                            ].filter(x => x.show)
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: menuCol.width
                                height: 30
                                radius: 8
                                Rectangle {
                                    visible: !!parent.modelData.sep && parent.index > 0
                                    width: parent.width - 16; x: 8; height: 1; y: -1
                                    color: Theme.stroke
                                }
                                color: item.containsMouse ? Theme.hover : "transparent"
                                Accessible.role: Accessible.MenuItem
                                Accessible.name: modelData.label
                                Accessible.onPressAction: { modelData.run(); win.menuFor = -1; }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 10
                                    text: parent.modelData.label
                                    width: parent.width - 20
                                    elide: Text.ElideRight
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 12 * Theme.fontScale
                                }
                                MouseArea {
                                    id: item
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { parent.modelData.run(); win.menuFor = -1; }
                                }
                                KeyFocus { radius: 8; onActivated: { parent.modelData.run(); win.menuFor = -1; } }
                            }
                        }
                    }
                }
                ToolTipText {
                    visible: area.containsMouse && win.menuFor < 0
                    text: cell.modelData.entry ? cell.modelData.entry.name : cell.modelData.id
                }
            }
        }


        // the shelf (Yoink's, in the dock): drop files here to keep them for later;
        // they wait at the top of the sidebar's Shelf, and drag out from there
        DockTile {
            id: shelfTile
            tip: Shelf.parked.length ? Tr.t("Shelf: %1 kept for later - drop more here", Shelf.parked.length)
                                     : Tr.t("Shelf: drop files here to keep them for later")
            Accessible.name: Tr.t("Shelf")
            on: shelfDrop.containsDrag
            onActivated: Ui.toggleControlCenter()
            Icon { anchors.centerIn: parent; name: "user-bookmarks"; size: parent.width * 0.46; color: shelfTile.on ? Theme.accent : Theme.text }
            Rectangle {
                visible: Shelf.parked.length > 0
                anchors.right: parent.right; anchors.top: parent.top
                width: Math.max(16, countText.implicitWidth + 8); height: 16; radius: 8
                color: Theme.accent
                Text { id: countText; anchors.centerIn: parent; text: Shelf.parked.length; color: Theme.accentInk; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale; font.weight: Font.DemiBold }
            }
            DropArea {
                id: shelfDrop
                anchors.fill: parent
                onEntered: d => { win.dropsIn++; d.accept(d.hasUrls ? Qt.CopyAction : Qt.IgnoreAction); }
                onExited: { win.dropsIn = Math.max(0, win.dropsIn - 1); dragOff.restart(); }
                onDropped: d => { win.dropsIn = 0; win.dragging = false; Shelf.park(d.urls); d.acceptProposedAction(); }
            }
        }
        DockSeparator {}
        Repeater {
            model: win.spaces.concat([null])
            DockTile {
                id: wsCell
                required property var modelData
                required property int index
                readonly property bool plus: modelData === null
                readonly property var wins: plus ? [] : win.windowsOn(modelData)
                on: !plus && modelData.is_active
                tip: plus ? Tr.t("New workspace") : on ? Tr.t("All workspaces") : Tr.t("Workspace %1", index + 1)
                Accessible.name: plus ? Tr.t("New workspace")
                    : Tr.t("Workspace %1", index + 1) + ", " + (wins.length === 1 ? Tr.t("1 window") : Tr.t("%1 windows", wins.length))
                onActivated: {
                    if (plus) win.newWorkspace();
                    else if (on) Niri.action("toggle-overview");
                    else Niri.focusWorkspace(modelData);
                }
                Icon {
                    visible: wsCell.plus
                    anchors.centerIn: parent
                    name: "list-add"
                    size: parent.width * 0.42
                    color: Theme.dim
                }
                // nothing open there: its number
                Text {
                    visible: !wsCell.plus && wsCell.wins.length === 0
                    anchors.centerIn: parent
                    text: wsCell.index + 1
                    color: wsCell.on ? Theme.accent : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: parent.height * 0.4
                    font.weight: Font.DemiBold
                }
                Grid {
                    visible: !wsCell.plus && wsCell.wins.length > 0
                    anchors.centerIn: parent
                    columns: 2
                    spacing: parent.width * 0.06
                    Repeater {
                        model: wsCell.wins.slice(0, 4)
                        AppIcon {
                            required property var modelData
                            readonly property var entry: win.entryOf(modelData.app_id || "")
                            implicitSize: wsCell.width * 0.34
                            icon: entry ? entry.icon : (modelData.app_id || "")
                            name: entry ? entry.name : (modelData.app_id || "")
                        }
                    }
                }
            }
        }
        // the trash, last: drop files to throw them away; a click opens it in
        // Files; right-click twice empties it. Watched by inotify, never polled.
        DockSeparator { visible: Settings.data.dockTrash }
        DockTile {
            id: trashTile
            visible: Settings.data.dockTrash
            property bool arming: false
            readonly property int count: trashFiles.count
            onCountChanged: Ui.trashCount = count
            tip: arming ? Tr.t("Right-click again to empty the trash")
                : count > 0 ? Tr.t("Trash: %1 - drop files here, right-click to empty").arg(count === 1 ? Tr.t("1 item") : Tr.t("%1 items").arg(count))
                : Tr.t("Trash is empty - drop files here")
            Accessible.name: Tr.t("Trash")
            on: trashDrop.containsDrag || arming
            onActivated: Qt.openUrlExternally("trash:///")
            readonly property string trashDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash/files"
            // made first: a FolderListModel on a folder that is not there lists / instead
            Process { running: true; command: ["mkdir", "-p", trashTile.trashDir]; onExited: trashFiles.folder = "file://" + trashTile.trashDir }
            FolderListModel {
                id: trashFiles
                showHidden: true
                showDirs: true
            }
            Icon { anchors.centerIn: parent; name: trashTile.count > 0 ? "user-trash-full" : "user-trash"; size: parent.width * 0.5; color: trashTile.arming ? Theme.danger : Theme.text }
            Timer { running: trashTile.arming; interval: 4000; onTriggered: trashTile.arming = false }
            // the Menu key (a controller's X) is the right-click: arm, then empty
            onMenuRequested: trashMenu.clicked(null)
            MouseArea {
                id: trashMenu
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: {
                    if (trashTile.count === 0)
                        return;
                    if (trashTile.arming) {
                        trashTile.arming = false;
                        Quickshell.execDetached(["gio", "trash", "--empty"]);
                    } else {
                        trashTile.arming = true;
                    }
                }
            }
            DropArea {
                id: trashDrop
                anchors.fill: parent
                onEntered: d => { win.dropsIn++; d.accept(d.hasUrls ? Qt.MoveAction : Qt.IgnoreAction); }
                onExited: { win.dropsIn = Math.max(0, win.dropsIn - 1); dragOff.restart(); }
                onDropped: d => {
                    win.dropsIn = 0; win.dragging = false;
                    Quickshell.execDetached(["gio", "trash"].concat(d.urls.map(u => String(u))));
                    d.acceptProposedAction();
                }
            }
        }
    }

    // an app-sized square for the dock's own controls: a soft translucent tile,
    // tinted with the accent when it is "on", lifted a touch under the pointer
    component DockTile: Item {
        id: tile
        property bool on: false
        property string tip: ""
        // the icon theme's own icon (Papirus has multitasking-view, show-desktop):
        // drawn like an app; the tile and its drawn glyph only where a theme has none
        property string icon: ""
        readonly property string themed: icon ? Quickshell.iconPath(icon, true) : ""
        signal activated()
        signal menuRequested()
        default property alias content: face.data
        width: win.base
        height: win.base
        IconImage {
            visible: tile.themed !== ""
            anchors.centerIn: parent
            implicitSize: win.base * (tileArea.pressed ? 0.94 : 1)
            source: tile.themed
            Behavior on implicitSize { NumberAnimation { duration: Theme.anim } }
        }
        // on (the overview open, the desktop shown): a pip below, like a running app
        Rectangle {
            visible: tile.themed !== "" && tile.on
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 2
            width: 14
            height: 4
            radius: 2
            color: Theme.accent
        }
        Accessible.role: Accessible.Button
        Accessible.name: tip
        Accessible.onPressAction: activated()
        Rectangle {
            id: face
            visible: tile.themed === ""
            anchors.fill: parent
            anchors.margins: win.base * 0.04
            radius: width * 0.24
            color: tile.on ? Theme.accentSoft : Theme.alpha(Theme.text, tileArea.containsMouse ? 0.14 : 0.08)
            border.width: tile.on ? 1.5 : 1
            border.color: tile.on ? Theme.accent : Theme.alpha(Theme.text, 0.08)
            scale: tileArea.pressed ? 0.94 : 1
            Behavior on color { ColorAnimation { duration: Theme.anim } }
            Behavior on scale { NumberAnimation { duration: Theme.anim } }
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
        KeyFocus { name: tile.Accessible.name; radius: width * 0.24; onActivated: tile.activated(); onMenu: tile.menuRequested() }
        ToolTipText { visible: tileArea.containsMouse; text: tile.tip }
    }

    component DockSeparator: Item {
        width: 13
        height: win.base
        Rectangle {
            anchors.centerIn: parent
            width: 1
            height: win.base * 0.56
            radius: 0.5
            color: Theme.alpha(Theme.text, 0.14)
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
            font.pixelSize: 11 * Theme.fontScale
        }
    }

    Rectangle {
        visible: hintTimer.running && !win.shown
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: hintRow.implicitWidth + 28
        height: hintRow.implicitHeight + 16
        radius: height / 2
        color: Theme.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Theme.accentLine
        Row {
            id: hintRow
            anchors.centerIn: parent
            spacing: 8
            Icon { name: "go-down"; size: 16; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
            Text { text: Tr.t("The dock steps aside for your windows — rest the pointer on the bottom edge to bring it back"); color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
        }
    }
}
