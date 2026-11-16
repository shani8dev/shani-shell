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
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
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
    // the home has the keys unless the shell's own overlays (the launcher, the
    // screen keyboard typing from the remote) are up over it
    WlrLayershell.keyboardFocus: visible && !Ui.launcher && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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
        return { key: "app:" + a.id, label: a.name || a.id, icon: a.icon || "application-x-executable",
                 run: () => { Launch.app(a.id); Ui.tvHome = false; } };
    }
    function settingsItem(label, icon, cat) {
        return { key: "settings:" + cat, label: label, icon: icon, run: () => { Ui.tvHome = false; Ui.openSettings(cat); } };
    }
    readonly property var shelves: {
        const open = Niri.mru().filter(w => w.app_id && w.app_id !== "org.quickshell").slice(0, 12).map(w => {
            const e = DesktopEntries.heuristicLookup(w.app_id || "");
            return { key: "window:" + w.id, label: e ? e.name : (w.title || w.app_id), icon: e ? e.icon : w.app_id,
                     subtitle: w.title || "", run: () => { Ui.tvHome = false; Niri.focusWin(w); } };
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
            { key: "power:reboot", label: Tr.t("Restart"), icon: "system-reboot", run: () => Power.reboot() },
            { key: "power:poweroff", label: Tr.t("Power off"), icon: "system-shutdown", run: () => Power.poweroff() },
            { key: "power:logout", label: Tr.t("Sign out"), icon: "system-log-out", run: () => Power.logout() }
        ];
        return [
            { id: "open", title: Tr.t("Open now"), big: true, items: open },
            { id: "pinned", title: Tr.t("Pinned"), big: true, items: pinned },
            { id: "games", title: Tr.t("Games"), items: games },
            { id: "apps", title: Tr.t("Apps"), items: apps.map(appItem) },
            { id: "settings", title: Tr.t("Settings"), items: settings },
            { id: "power", title: Tr.t("Power"), items: power }
        ].filter(s => s.items.length > 0);
    }

    // where the remote is: a shelf and a card in it (each shelf remembers its own)
    property int row: 0
    property var cols: ({})
    function colOf(r) { const s = shelves[r]; return s ? Math.min(cols[s.id] || 0, s.items.length - 1) : 0; }
    readonly property var current: shelves[Math.min(row, shelves.length - 1)] ? shelves[Math.min(row, shelves.length - 1)].items[colOf(Math.min(row, shelves.length - 1))] : null
    onCurrentChanged: if (visible) Ui.tvSelected = current ? current.key : ""
    onVisibleChanged: {
        if (visible) { row = 0; Ui.tvSelected = current ? current.key : ""; Qt.callLater(() => keys.forceActiveFocus()); }
    }
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
    function activate() { if (current) current.run(); }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            Ui.keysActivated = true;
            switch (e.key) {
            case Qt.Key_Left: win.move(0, -1); break;
            case Qt.Key_Right: win.move(0, 1); break;
            case Qt.Key_Up: win.move(-1, 0); break;
            case Qt.Key_Down: win.move(1, 0); break;
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: case Qt.Key_Space: win.activate(); break;
            case Qt.Key_Escape: case Qt.Key_Back: case Qt.Key_Backspace: if (win.shelves.length && win.shelves[0].id === "open") Ui.tvHome = false; break;
            default: return;
            }
            e.accepted = true;
        }

        // the top: the time, the date, and the status at a glance
        Row {
            id: top
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.px(40) }
            spacing: Theme.px(24)
            Column {
                Text {
                    text: Qt.formatTime(clock.date, Settings.data.use24h ? "HH:mm" : "h:mm")
                    color: Theme.text
                    font.pixelSize: Theme.px(44) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Qt.formatDate(clock.date, "dddd d MMMM")
                    color: Theme.dim
                    font.pixelSize: Theme.px(16) * Theme.fontScale
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
                font.pixelSize: Theme.px(18) * Theme.fontScale
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
            Behavior on contentY { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
                            font.pixelSize: Theme.px(20) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        ListView {
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
                                y: Theme.px(8)
                                width: shelf.modelData.big ? Theme.px(240) : Theme.px(150)
                                height: shelf.modelData.big ? Theme.px(150) : Theme.px(124)
                                radius: Theme.px(14)
                                color: here ? Theme.accentSoft : Theme.card
                                border.width: here ? Theme.px(3) : 1
                                border.color: here ? Theme.accent : Theme.border
                                scale: here ? 1.06 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.label
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
                                        font.pixelSize: Theme.px(14) * Theme.fontScale
                                    }
                                    Text {
                                        visible: !!card.modelData.subtitle && card.modelData.subtitle !== card.modelData.label
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: card.modelData.subtitle || ""
                                        color: Theme.dim
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: { win.row = shelf.index; const m = Object.assign({}, win.cols); m[shelf.modelData.id] = card.index; win.cols = m; }
                                    onClicked: { win.row = shelf.index; const m = Object.assign({}, win.cols); m[shelf.modelData.id] = card.index; win.cols = m; win.activate(); }
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
                ]
                delegate: Row {
                    required property var modelData
                    spacing: Theme.px(10)
                    Rectangle {
                        width: Math.max(Theme.px(32), keyText.implicitWidth + Theme.px(16))
                        height: Theme.px(32)
                        radius: height / 2
                        color: Theme.glassStrong
                        border.color: Theme.border
                        Text { id: keyText; anchors.centerIn: parent; text: modelData.key; color: Theme.text; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.what; color: Theme.dim; font.pixelSize: Theme.px(15) * Theme.fontScale }
                }
            }
        }
    }
}
