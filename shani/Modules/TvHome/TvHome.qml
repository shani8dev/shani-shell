// The TV home (docs/FORM-FACTORS.md, step 2): on a screen whose kind is TV, a
// full-screen 10-foot home after Android TV / Big Picture - shelves of what is
// open, pinned apps, games, every app, settings and power; the clock and status
// on top; what the buttons do below. Driven by the remote's arrows / OK / Back /
// Home (niri binds -> remote* IPC) and the controller (GamepadNav sends the same
// keys), and by mouse or touch. It replaces the console's own sway home on the
// gamescope image: that desktop mode is this shell with its screen set to TV.
//
// Shown on a TV screen at start and on Home; opening anything hides it, and Back
// hides it when there is something behind it to go back to.
//
// The upgrade (the remote's Menu is reorder mode): the opened card pulses,
// grab-and-drag reorders a shelf's menu, sounds go with the main actions, the
// clock is padded to two digits with the locale's AM/PM, the quickview opens
// the open window in front of the home (Close / Focus), F3 turns the
// "open now" list off and back on, and pressing keys to open an app takes the
// screen fullscreen (Niri).
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    required property var modelData
    screen: modelData
    // a TV, and a handheld (the same home at arm's length, at its own scale)
    readonly property bool tv: FormFactor.tenFootKind(FormFactor.of(modelData.name).profile)
    visible: tv && Ui.tvHome && !Lock.locked && !Ui.quickPanel
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-tv-home"
    // over the bar, the island and the dock (the 10-foot home is the whole screen);
    // the launcher, the screen keyboard and pop-ups, made after it, still open over it
    WlrLayershell.layer: WlrLayer.Overlay
    // every TV output gets a home window; only the focused one takes the remote's
    // keys (two Exclusive surfaces fight over each press on a second TV)
    readonly property bool keysHere: !Niri.focusedOutput || Niri.focusedOutput === modelData.name
    // the home has the keys unless the shell's own overlays (the launcher, the
    // screen keyboard typing from the remote) are up over it
    WlrLayershell.keyboardFocus: visible && keysHere && !Ui.launcher && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // the shelves: { id, title, items: [{ label, icon, run() }] }; empty ones are left out
    // one card per app name: two entries of the same app (a Flatpak and the
    // native build, an alias) would be two identical cards
    readonly property var apps: {
        const seen = {};
        return DesktopEntries.applications.values
            .filter(a => !a.noDisplay && AppFilter.allowed(a.id))
            .sort((a, b) => (a.name || "").localeCompare(b.name || ""))
            .filter(a => { const k = (a.name || a.id).toLowerCase(); if (seen[k]) return false; seen[k] = true; return true; });
    }
    function appItem(a) {
        return { key: "app:" + a.id, label: a.name || a.id, icon: AppIconPath.nameFor(a, "application-x-executable"),
                 run: () => win.openApp(a) };
    }
    function settingsItem(label, icon, cat) {
        return { key: "settings:" + cat, label: label, icon: icon,
                 run: () => { win.settingsFromHome = true; Ui.tvHome = false; Ui.openSettings(cat); } };
    }
    readonly property var shelves: {
        const open = Niri.mru().filter(w => w.app_id && w.app_id !== "org.quickshell").slice(0, 12).map(w => {
            const e = DesktopEntries.heuristicLookup(w.app_id || "");
            return { key: "window:" + w.id, label: e ? e.name : (w.title || w.app_id), icon: e ? e.icon : w.app_id,
                     subtitle: w.title || "", w: w, run: () => { Ui.tvHome = false; Niri.focusWin(w); } };
        });
        const pinned = (Settings.data.dockPinned || []).map(id => DesktopEntries.byId(id)).filter(e => e && AppFilter.allowed(e.id)).map(appItem);
        const games = apps.filter(a => [].concat(a.categories || []).indexOf("Game") >= 0).map(appItem);
        const settings = [
            settingsItem(Tr.t("Network"), "network-wireless", "network"),
            settingsItem(Tr.t("Sound"), "audio-speakers", "sound"),
            settingsItem(Tr.t("Screens"), "video-display", "displays"),
            settingsItem(Tr.t("Controllers & input"), "input-gaming", "input"),
            settingsItem(Tr.t("Accessibility"), "preferences-desktop-accessibility", "access"),
            settingsItem(Tr.t("All settings"), "preferences-system", "personal")
        ];
        const power = [
            { key: "power:suspend", label: Tr.t("Sleep"), icon: "system-suspend", run: () => { Ui.tvHome = false; Power.suspend(); } },
            { key: "power:reboot", label: Tr.t("Restart"), icon: "system-reboot", run: () => { Ui.tvHome = false; Power.reboot(); } },
            { key: "power:poweroff", label: Tr.t("Power off"), icon: "system-shutdown", run: () => { Ui.tvHome = false; Power.poweroff(); } },
            { key: "power:logout", label: Tr.t("Sign out"), icon: "system-log-out", run: () => { Ui.tvHome = false; Power.logout(); } }
        ];
        return [
            { id: "open", title: Tr.t("Open now"), big: true, items: win.ordered("open", open) },
            { id: "pinned", title: Tr.t("Pinned"), big: true, items: win.ordered("pinned", pinned) },
            { id: "games", title: Tr.t("Games"), items: win.ordered("games", games) },
            { id: "apps", title: Tr.t("Apps"), items: win.ordered("apps", apps.map(appItem)) },
            { id: "settings", title: Tr.t("Settings"), items: settings },
            { id: "power", title: Tr.t("Power"), items: power }
        ].filter(s => s.items.length > 0 && !(s.id === "open" && win.noList));
    }

    // ---- the TV home's own state (remote, mouse and keyboard all drive it) ----
    // F3 turns the "open now" list off and on again (the "nolist" view: with it,
    // the home starts on the apps and games shelves, not the windows you have open)
    property bool noList: false
    // the remote's Menu: reorder mode - Left/Right move the current card, Enter
    // finishes, Back leaves the mode
    property bool reorder: false
    // grab-and-drag reorder: a shelf's menu items in the order the remote left
    // them (a plain array per shelf id; shelves without an entry keep their order)
    property var order: ({})
    function ordered(id, items) {
        const keys = win.order[id];
        if (!keys || !keys.length) return items;
        const byKey = {};
        items.forEach(i => { if (i.key) byKey[i.key] = i; });
        const out = keys.map(k => byKey[k]).filter(x => x);
        items.forEach(i => { if (i.key && out.indexOf(i) < 0) out.push(i); });
        return out;
    }
    // reorder the shelf at win.row by delta from the current card, writing the
    // order back to win.order so the next shelves recompute it
    function reorderCurrent(delta) {
        const s = shelves[row];
        const c = current;
        if (!s || !c || !c.key) return false;
        const idx = s.items.findIndex(i => i.key === c.key);
        if (idx < 0) return false;
        const list = (win.order[s.id] || []).slice();
        if (list.length < s.items.length) list.push(...s.items.map(i => i.key));
        const to = Math.max(0, Math.min(list.length - 1, idx + delta));
        const a = idx, b = to;
        const tmp = list[a]; list[a] = list[b]; list[b] = tmp;
        win.order = Object.assign({}, win.order, { [s.id]: list });
        const m = Object.assign({}, cols);
        m[s.id] = to;
        cols = m;
        SystemSounds.play("bell");
        return true;
    }
    // the open-and-pulse of a card: activate() bumps openedAt and the opened card
    // pulses for a beat (the "highlight when the app opens")
    property int openedAt: 0
    property string pulseKey: ""
    property int pulseStep: 0
    Timer { id: pulseTimer; interval: Theme.mot(150); running: win.pulseStep > 0; onTriggered: { win.pulseStep--; if (win.pulseStep <= 0) win.pulseKey = ""; } }
    property string toastMsg: ""
    function toast(msg) { win.toastMsg = msg; }
    // opening an app by key (the remote's OK / Enter): after the app opens, take
    // the screen for it the way Android TV does when you open from the launcher
    property string pendingApp: ""
    Timer { id: openTimer; interval: 320; onTriggered: Niri.fullscreenWindow(win.pendingApp); }
    function openApp(a) {
        Launch.app(a.id);
        win.pendingApp = a.id;
        Ui.tvHome = false;
    }
    function activate(viaKeys) {
        const c = current;
        if (!c) return;
        win.openedAt++;
        win.pulseKey = c.key;
        win.pulseStep = 6;
        SystemSounds.play(viaKeys ? "bell" : "complete");
        c.run();
        openTimer.restart();
        win.toast(Tr.t("Opening %1").arg(c.label));
    }
    // the quickview (a window card in the "open now" shelf, opened by a double
    // tap or F5): the window in front of the home, Close or Focus it
    property var quick: null
    property bool quickOpen: false
    function openQuick() {
        const c = current;
        if (!c || !c.w) return;
        win.quick = c;
        win.quickOpen = true;
        SystemSounds.play("dialog-information");
    }
    function closeQuick(what) { win.quickOpen = false; if (win.quick) what(win.quick.w); win.quick = null; }
    // the time, padded to two digits, with the locale's AM/PM when not 24-hour
    function amText() {
        if (Settings.data.use24h) return "";
        const loc = Qt.locale();
        const t = loc && loc.amText;
        return t ? " " + (typeof t === "function" ? t.call(loc) : t) : " " + Tr.t("AM");
    }
    property string timeText: Settings.data.use24h
        ? Qt.formatTime(clock.date, "HH:mm")
        : Qt.formatTime(clock.date, "hh:mm") + win.amText()

    // where the remote is: a shelf and a card in it (each shelf remembers its own)
    property int row: 0
    property var cols: ({})
    function colOf(r) { const s = shelves[r]; return s ? Math.min(cols[s.id] || 0, s.items.length - 1) : 0; }
    readonly property var current: shelves[Math.min(row, shelves.length - 1)] ? shelves[Math.min(row, shelves.length - 1)].items[colOf(Math.min(row, shelves.length - 1))] : null
    onCurrentChanged: if (visible) Ui.tvSelected = current ? current.key : ""
    onVisibleChanged: {
        if (visible) { row = 0; Ui.tvSelected = current ? current.key : ""; if (keysHere) Qt.callLater(() => keys.forceActiveFocus()); }
        else Ui.tvSelected = "";
    }
    onShelvesChanged: {
        if (!shelves.length) { row = 0; return; }
        if (row >= shelves.length) row = shelves.length - 1;
        if (row < 0) row = 0;
    }
    onKeysHereChanged: if (keysHere && visible) Qt.callLater(() => keys.forceActiveFocus())
    function move(dr, dc) {
        if (!shelves.length) return;
        if (dr) {
            row = Math.max(0, Math.min(shelves.length - 1, row + dr));
        } else {
            const s = shelves[row];
            const m = Object.assign({}, cols);
            m[s.id] = Math.max(0, Math.min(s.items.length - 1, colOf(row) + dc));
            cols = m;
        }
    }

    // Settings closes itself with Ui.settingsOpen = false and never restores the
    // home (the Quick Panel does): coming back from a category we opened should
    // land on the home, not on a bare desktop with no window behind it
    property bool settingsFromHome: false
    Connections {
        target: Ui
        function onSettingsOpenChanged() {
            if (Ui.settingsOpen || !win.settingsFromHome) return;
            win.settingsFromHome = false;
            if (FormFactor.tenFoot && !Lock.locked
                && !Niri.mru().some(w => w.app_id && w.app_id !== "org.quickshell"))
                Ui.tvHome = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            switch (e.key) {
            case Qt.Key_Left: win.reorder ? win.reorderCurrent(-1) : win.move(0, -1); break;
            case Qt.Key_Right: win.reorder ? win.reorderCurrent(1) : win.move(0, 1); break;
            case Qt.Key_Up: win.move(-1, 0); break;
            case Qt.Key_Down: win.move(1, 0); break;
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: case Qt.Key_Space: win.activate(true); break;
            case Qt.Key_Escape: case Qt.Key_Back: case Qt.Key_Backspace:
                if (win.quickOpen) win.closeQuick();
                else if (win.reorder) win.reorder = false;
                else if (win.shelves.length && win.shelves[0].id === "open") Ui.tvHome = false;
                break;
            case Qt.Key_Menu: win.reorder = !win.reorder; SystemSounds.play("bell"); break;
            case Qt.Key_F3: win.noList = !win.noList; SystemSounds.play("bell"); break;
            case Qt.Key_F5: win.openQuick(); break;
            default: return;
            }
            // KeyFocus clears this after the control it opened has read it; do
            // the same here, or the flag stays set and the next OSK toggle opens
            // in remote mode however the person got there
            Ui.keysActivated = true;
            Qt.callLater(() => Ui.keysActivated = false);
            e.accepted = true;
        }

        // the top: the time, the date, and the status at a glance
        Row {
            id: top
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.px(40) }
            spacing: Theme.px(24)
            Column {
                Text {
                    text: win.timeText
                    color: Theme.text
                    font.pixelSize: Theme.px(44) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Qt.formatDate(clock.date, "dddd d MMMM")
                    color: Theme.dim
                    font.pixelSize: Theme.type("heading")
                }
            }
        }
        Row {
            anchors { top: parent.top; right: parent.right; margins: Theme.px(48) }
            spacing: Theme.px(20)
            Icon { name: Net.icon; size: Theme.px(26); anchors.verticalCenter: parent.verticalCenter }
            Text {
                visible: Power.hasBattery
                text: Math.round(Power.percent * 100) + "%"
                color: Theme.text
                font.pixelSize: Theme.type("subtitle")
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        SystemClock { id: clock; precision: SystemClock.Minutes }

        // the shelves, the one with the remote kept in view
        Flickable {
            id: list
            anchors { top: top.bottom; topMargin: Theme.px(24); left: parent.left; right: parent.right; bottom: hints.top; bottomMargin: Theme.px(16) }
            contentHeight: column.height
            clip: true
            interactive: true
            readonly property Item currentShelf: rows.itemAt(win.row)
            onCurrentShelfChanged: Qt.callLater(follow)
            function follow() {
                const s = rows.itemAt(win.row);
                if (!s) return;
                const want = Math.max(0, Math.min(contentHeight - height, s.y - Theme.px(12)));
                contentY = want;
            }
            Behavior on contentY { NumberAnimation { duration: Theme.mot(180); easing.type: Easing.OutCubic } }
            Column {
                id: column
                width: list.width
                spacing: Theme.px(28)
                Repeater {
                    id: rows
                    model: win.shelves
                    delegate: Column {
                        id: shelf
                        required property var modelData
                        required property int index
                        readonly property bool active: index === win.row
                        width: column.width
                        spacing: Theme.px(12)
                        Text {
                            x: Theme.px(48)
                            text: shelf.modelData.title
                            color: shelf.active ? Theme.text : Theme.dim
                            font.pixelSize: Theme.type("subtitle")
                            font.weight: Font.DemiBold
                        }
                        ListView {
                            reuseItems: true
                            cacheBuffer: 400
                            id: cards
                            width: parent.width
                            height: (shelf.modelData.big ? Theme.px(150) : Theme.px(124)) + Theme.px(16)
                            orientation: ListView.Horizontal
                            spacing: Theme.px(18)
                            leftMargin: Theme.px(48)
                            rightMargin: Theme.px(48)
                            model: shelf.modelData.items
                            currentIndex: win.colOf(shelf.index)
                            highlightMoveDuration: 160
                            preferredHighlightBegin: Theme.px(48)
                            preferredHighlightEnd: width - Theme.px(48)
                            highlightRangeMode: ListView.ApplyRange
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                required property int index
                                readonly property bool here: shelf.active && index === cards.currentIndex
                                // the open pulse: this card grew when its app opened
                                readonly property bool pulse: here && win.pulseKey === card.modelData.key && win.pulseStep > 0
                                function choose() {
                                    win.row = shelf.index;
                                    const m = Object.assign({}, win.cols);
                                    m[shelf.modelData.id] = card.index;
                                    win.cols = m;
                                }
                                y: Theme.px(8)
                                width: shelf.modelData.big ? Theme.px(240) : Theme.px(150)
                                height: shelf.modelData.big ? Theme.px(150) : Theme.px(124)
                                radius: Theme.px(14)
                                color: here ? Theme.accentSoft : Theme.card
                                border.width: here ? Theme.px(3) : 1
                                border.color: here ? Theme.accent : Theme.border
                                scale: here ? 1.06 * (pulse ? 1.28 : 1) : 1.0
                                Behavior on scale { NumberAnimation { duration: Theme.mot(120) } }
                                // grab-and-drag reorder (the mouse): a horizontal
                                // flick of the card moves it in its shelf
                                DragHandler {
                                    id: drag
                                    cursorShape: Qt.PointingHandCursor
                                    onActiveChanged: if (active && Math.abs(translation.x) > Theme.px(56))
                                        win.reorderCurrent(translation.x > 0 ? 1 : -1);
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.subtitle && modelData.subtitle !== modelData.label
                                    ? modelData.label + " — " + modelData.subtitle : modelData.label
                                // a screen reader must be able to open a card too, not
                                // just hear its name (the same path as a mouse click)
                                Accessible.onPressAction: { card.choose(); win.activate(); }
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - Theme.px(16)
                                    spacing: Theme.px(8)
                                    AppIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        icon: card.modelData.icon || ""
                                        name: card.modelData.label
                                        implicitSize: shelf.modelData.big ? Theme.px(64) : Theme.px(52)
                                    }
                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: card.modelData.label
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.type("heading")
                                    }
                                    Text {
                                        visible: !!card.modelData.subtitle && card.modelData.subtitle !== card.modelData.label
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: card.modelData.subtitle || ""
                                        color: Theme.dim
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.type("small")
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: card.choose()
                                    onClicked: { card.choose(); win.activate(); }
                                    onDoubleClicked: win.openQuick();
                                }
                            }
                        }
                    }
                }
                Item { width: 1; height: Theme.px(24) }
            }
        }

        // what the buttons do, in the words of what was last pressed
        Row {
            id: hints
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.px(28) }
            spacing: Theme.px(36)
            Repeater {
                model: [
                    { key: GamepadNav.controllers > 0 ? "A" : "OK", what: Tr.t("Open") },
                    { key: GamepadNav.controllers > 0 ? "B" : "↩", what: Tr.t("Back") },
                    { key: "⌂", what: Tr.t("Home") }
                ].concat(InputPlumber.managing && InputPlumber.navWanted
                    ? [{ key: "Start", what: Tr.t("Quick settings") }] : [])
                    .concat(win.reorder ? [
                        { key: "←→", what: Tr.t("Move") },
                        { key: "⏎", what: Tr.t("Done") }
                    ] : [{ key: "Menu", what: Tr.t("Reorder") }])
                    .concat([{ key: "F3", what: win.noList ? Tr.t("List") : Tr.t("No list") }])
                delegate: Row {
                    required property var modelData
                    spacing: Theme.px(10)
                    Rectangle {
                        width: Math.max(Theme.px(32), keyText.implicitWidth + Theme.px(16))
                        height: Theme.px(32)
                        radius: height / 2
                        color: Theme.glassStrong
                        border.color: Theme.border
                        Text { id: keyText; anchors.centerIn: parent; text: modelData.key; color: Theme.text; font.pixelSize: Theme.type("body"); font.weight: Font.DemiBold }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.what; color: Theme.dim; font.pixelSize: Theme.type("heading") }
                }
            }
        }

        // the quickview (a window card in the "open now" shelf): the window in
        // front of the home with its Close / Focus, over the bottom of the home
        Rectangle {
            id: quickview
            visible: win.quickOpen
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.px(96) }
            width: parent.width - Theme.px(180)
            height: Theme.px(190)
            radius: Theme.px(16)
            color: Theme.glassStrong
            border.width: 1
            border.color: win.quick ? Theme.accent : Theme.border
            Column {
                anchors.fill: parent
                anchors.margins: Theme.px(18)
                spacing: Theme.px(12)
                Text {
                    text: win.quick ? (win.quick.subtitle || win.quick.label) : ""
                    color: Theme.text
                    font.pixelSize: Theme.type("subtitle")
                    font.weight: Font.DemiBold
                }
                Text {
                    text: win.quick ? win.quick.label : ""
                    color: Theme.dim
                    font.pixelSize: Theme.type("body")
                }
                Row {
                    spacing: Theme.px(24)
                    Repeater {
                        model: [
                            { what: Tr.t("Close"), run: () => win.closeQuick(w => Niri.action("close-window", "--id", w.id)) },
                            { what: Tr.t("Focus"), run: () => win.closeQuick(w => Niri.focusWin(w)) }
                        ]
                        delegate: Rectangle {
                            id: qbtn
                            required property var modelData
                            color: Theme.accentSoft
                            border.width: 1
                            border.color: Theme.accent
                            radius: Theme.px(10)
                            implicitWidth: Theme.px(130)
                            height: Theme.px(42)
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: modelData.run() }
                            Text { anchors.centerIn: parent; text: modelData.what; color: Theme.text; font.pixelSize: Theme.type("heading") }
                        }
                    }
                }
            }
        }

        // the toasts for what the home's cards did
        Toast {
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.px(24) }
            z: 10
            message: win.toastMsg
        }
    }
}
