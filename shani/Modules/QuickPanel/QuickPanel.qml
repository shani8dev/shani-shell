// The quick panel (docs/FORM-FACTORS.md, step 3): on a handheld or a TV, the
// ⋯ / Quick Access button opens this over whatever is running - a game keeps
// running behind it. Brightness, volume, performance, the screen keyboard, and
// back to the home or out of the app; the battery and the time on top.
// Up / Down pick a row, Left / Right change it, A (OK) does it, B (Back) closes;
// touch and the mouse work on every row.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services
import "../../Common/Gestures.js" as G
import "../../Common/Tools.js" as Tools

PanelWindow {
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    // Tools.list owns the first four labels, icons and order.
    readonly property var toolRuns: ({
        dictionary: () => { Ui.closeAll(); Ui.dictionary = true; },
        podcasts: () => { Ui.closeAll(); Ui.podcasts = true; },
        teleprompter: () => { Ui.closeAll(); Ui.teleprompter = true; },
        netTools: () => { Ui.closeAll(); Ui.netTools = true; }
    })
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    visible: Ui.quickPanel && !Lock.locked
    anchors { top: true; bottom: true; right: true }
    implicitWidth: Math.min(Theme.px(360), screen ? screen.width : Theme.px(360))
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-quick-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // { key, label, icon, value (0..1, or -1 for a button), text, adjust(d), run() }
    readonly property var rows: {
        const r = [];
        if (Brightness.available)
            r.push({ key: "brightness", label: Tr.t("Brightness"), icon: "display-brightness", value: Brightness.value,
                     text: Math.round(Brightness.value * 100) + "%",
                     adjust: d => Brightness.set(Math.max(0.05, Math.min(1, Brightness.value + d * 0.05))), run: null });
        r.push({ key: "volume", label: Tr.t("Volume"), icon: Audio.icon, value: Audio.muted ? 0 : Audio.volume / Audio.maxVolume,
                 text: Audio.muted ? Tr.t("Muted") : Math.round(Audio.volume * 100) + "%",
                 adjust: d => Audio.setVolume(Math.max(0, Math.min(Audio.maxVolume, Audio.volume + d * 0.05))),
                 run: () => Audio.toggleMute() });
        r.push({ key: "performance", label: Tr.t("Performance"), icon: Power.profileIcon, value: -1,
                 text: Tr.t(Power.profileName), adjust: d => Power.cycleProfile(), run: () => Power.cycleProfile() });
        r.push({ key: "keyboard", label: Tr.t("Screen keyboard"), icon: "input-keyboard", value: -1,
                 text: Osk.shown ? Tr.t("On") : Tr.t("Off"), adjust: null, run: () => { Ui.quickPanel = false; Osk.toggle(); } });
        r.push({ key: "home", label: Tr.t("Home"), icon: "go-home", value: -1, text: "",
                 adjust: null, run: () => { Ui.quickPanel = false; Ui.tvHome = true; } });
        // the app behind (the panel has the keys, so niri reports no focused window)
        const app = Niri.mru().find(w => w.app_id && w.app_id !== "org.quickshell");
        if (app)
            r.push({ key: "close", label: Tr.t("Close %1").arg(app.title || app.app_id),
                     icon: "window-close", value: -1, text: "", adjust: null,
                     run: () => { Ui.quickPanel = false; Niri.action("close-window", "--id", String(app.id)); } });
        return r;
    }
    // `rows` is rebuilt whenever a level or device changes. Feeding that new JS
    // array straight to the Repeater destroys every delegate on each adjust, so
    // a slider press loses its MouseArea after the first step. Keep the model as
    // plain indices - it only changes when rows are added or removed.
    property var rowIndexes: []
    onRowsChanged: {
        if (rows.length > 0)
            sel = Math.min(sel, rows.length - 1);
        if (rowIndexes.length === rows.length)
            return;
        const idx = [];
        for (let i = 0; i < rows.length; i++)
            idx.push(i);
        rowIndexes = idx;
    }
    property int sel: 0
    readonly property var current: rows[Math.min(sel, rows.length - 1)] || null
    onCurrentChanged: Ui.quickSelected = visible && current ? current.key : ""
    onVisibleChanged: {
        sel = 0;
        Ui.quickSelected = visible && current ? current.key : "";
        if (visible) Qt.callLater(() => keys.forceActiveFocus());
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: Theme.px(12)
        radius: Theme.px(18)
        // near-opaque: over a game, the bar and the game must not show through the words
        color: Theme.alpha(Theme.bg, 0.97)
        border.color: Theme.border
        Accessible.role: Accessible.Dialog
        Accessible.name: Tr.t("Quick panel")

        // a finger swipes it away (right); the mouse and the pen keep their drags
        DragHandler {
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            acceptedDevices: PointerDevice.TouchScreen
            onActiveChanged: if (!active && G.dismissed("right", translation.x, translation.y, Theme.px(80))) Ui.closeAll()
        }
        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                const c = win.current;
                switch (e.key) {
                case Qt.Key_Up: win.sel = Math.max(0, win.sel - 1); break;
                case Qt.Key_Down: win.sel = Math.min(win.rows.length - 1, win.sel + 1); break;
                case Qt.Key_Left: if (c && c.adjust) c.adjust(-1); break;
                case Qt.Key_Right: if (c && c.adjust) c.adjust(1); break;
                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: case Qt.Key_Space:
                    if (c && c.run) c.run(); else if (c && c.adjust) c.adjust(1);
                    break;
                case Qt.Key_Escape: case Qt.Key_Back: Ui.quickPanel = false; break;
                default: return;
                }
                e.accepted = true;
            }

            Column {
                anchors { fill: parent; margins: Theme.px(18) }
                spacing: Theme.px(10)

                // the time and the battery
                Item {
                    width: parent.width
                    height: Theme.px(40)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatTime(clock.date, Settings.data.use24h ? "HH:mm" : "h:mm")
                        color: Theme.text
                        font.pixelSize: Theme.px(24) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: Theme.px(6)
                        visible: Power.hasBattery
                        Icon { name: Power.charging ? "battery-good-charging" : "battery-good"; size: Theme.px(20); anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: Math.round(Power.percent * 100) + "%"
                            color: Theme.text
                            font.pixelSize: Theme.px(16) * Theme.fontScale
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    SystemClock { id: clock; precision: SystemClock.Minutes }
                }

                Repeater {
                    model: win.rowIndexes
                    delegate: Rectangle {
                        id: row
                        required property int modelData
                        required property int index
                        // data is looked up live: the Repeater model stays put while a
                        // level is being dragged, but these values still track services
                        readonly property var rowData: win.rows[modelData] || ({ key: "", label: "", icon: "", value: -1, text: "", adjust: null, run: null })
                        readonly property bool here: index === win.sel
                        width: parent.width
                        height: rowData.value >= 0 ? Theme.px(72) : Theme.px(52)
                        radius: Theme.px(12)
                        color: here ? Theme.accentSoft : "transparent"
                        border.width: here ? Theme.px(2) : 0
                        border.color: Theme.accent
                        Accessible.role: rowData.value >= 0 ? Accessible.Slider : Accessible.Button
                        Accessible.name: rowData.label
                        Accessible.description: rowData.value < 0 ? (rowData.text || "") : ""
                        Accessible.selected: here
                        Accessible.onPressAction: {
                            if (rowData.run) rowData.run();
                            else if (rowData.adjust) rowData.adjust(1);
                        }
                        Row {
                            id: head
                            x: Theme.px(12)
                            y: rowData.value >= 0 ? Theme.px(10) : (parent.height - height) / 2
                            spacing: Theme.px(10)
                            Icon { name: row.rowData.icon; size: Theme.px(20); anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                width: row.width - Theme.px(110)
                                text: row.rowData.label
                                color: Theme.text
                                elide: Text.ElideRight
                                font.pixelSize: Theme.px(15) * Theme.fontScale
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: Theme.px(14) }
                            y: head.y + (head.height - height) / 2
                            text: row.rowData.text
                            color: Theme.dim
                            font.pixelSize: Theme.px(14) * Theme.fontScale
                        }
                        // a level: a track to drag along, as well as Left / Right
                        Rectangle {
                            id: track
                            visible: row.rowData.value >= 0
                            anchors { left: parent.left; right: parent.right; margins: Theme.px(14) }
                            y: parent.height - Theme.px(20)
                            height: Theme.px(6)
                            radius: height / 2
                            color: Theme.alpha(Theme.text, 0.15)
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, row.rowData.value))
                                height: parent.height
                                radius: parent.radius
                                color: Theme.accent
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed: m => { win.sel = row.index; if (row.rowData.value >= 0) setTo(m.x); }
                            onPositionChanged: m => { if (pressed && row.rowData.value >= 0) setTo(m.x); }
                            onClicked: if (row.rowData.value < 0 && row.rowData.run) row.rowData.run()
                            // dragging a level: as many steps as it takes to get there
                            function setTo(x) {
                                const want = Math.max(0, Math.min(1, (x - track.x) / track.width));
                                const steps = Math.round((want - row.rowData.value) / 0.05);
                                if (steps !== 0 && row.rowData.adjust) row.rowData.adjust(steps);
                            }
                        }
                    }
                }

                // More apps: the four tools people reach for most. A compact row
                // of icon buttons that fits the same column as the tile rows.
                Row {
                    width: parent.width
                    spacing: Theme.px(8)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("More apps")
                        color: Theme.dim
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    Repeater {
                        model: Tools.list.slice(0, 4).map(t => ({
                                label: Tr.t(t.label), icon: t.icon, run: toolRuns[t.flag]
                            }))
                        delegate: Rectangle {
                            required property var modelData
                            width: Theme.px(44); height: Theme.px(36)
                            radius: Theme.px(8)
                            color: Theme.alpha(Theme.text, 0.08)
                            Icon { anchors.centerIn: parent; name: modelData.icon; size: Theme.px(18) }
                            MouseArea { anchors.fill: parent; onClicked: modelData.run() }
                            KeyFocus { name: modelData.label; onActivated: modelData.run() }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.label
                        }
                    }
                }
            }
        }
    }
}
