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

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    visible: Ui.quickPanel && !Lock.locked
    anchors { top: true; bottom: true; right: true }
    implicitWidth: Theme.px(360)
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
                    model: win.rows
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool here: index === win.sel
                        width: parent.width
                        height: modelData.value >= 0 ? Theme.px(72) : Theme.px(52)
                        radius: Theme.px(12)
                        color: here ? Theme.accentSoft : "transparent"
                        border.width: here ? Theme.px(2) : 0
                        border.color: Theme.accent
                        Accessible.role: modelData.value >= 0 ? Accessible.Slider : Accessible.Button
                        Accessible.name: modelData.label
                        Row {
                            id: head
                            x: Theme.px(12)
                            y: modelData.value >= 0 ? Theme.px(10) : (parent.height - height) / 2
                            spacing: Theme.px(10)
                            Icon { name: row.modelData.icon; size: Theme.px(20); anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                width: row.width - Theme.px(110)
                                text: row.modelData.label
                                color: Theme.text
                                elide: Text.ElideRight
                                font.pixelSize: Theme.px(15) * Theme.fontScale
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: Theme.px(14) }
                            y: head.y + (head.height - height) / 2
                            text: row.modelData.text
                            color: Theme.dim
                            font.pixelSize: Theme.px(14) * Theme.fontScale
                        }
                        // a level: a track to drag along, as well as Left / Right
                        Rectangle {
                            id: track
                            visible: row.modelData.value >= 0
                            anchors { left: parent.left; right: parent.right; margins: Theme.px(14) }
                            y: parent.height - Theme.px(20)
                            height: Theme.px(6)
                            radius: height / 2
                            color: Theme.alpha(Theme.text, 0.15)
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, row.modelData.value))
                                height: parent.height
                                radius: parent.radius
                                color: Theme.accent
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed: m => { win.sel = row.index; if (row.modelData.value >= 0) setTo(m.x); }
                            onPositionChanged: m => { if (pressed && row.modelData.value >= 0) setTo(m.x); }
                            onClicked: if (row.modelData.value < 0 && row.modelData.run) row.modelData.run()
                            // dragging a level: as many steps as it takes to get there
                            function setTo(x) {
                                const want = Math.max(0, Math.min(1, (x - track.x) / track.width));
                                const steps = Math.round((want - row.modelData.value) / 0.05);
                                if (steps !== 0 && row.modelData.adjust) row.modelData.adjust(steps);
                            }
                        }
                    }
                }
            }
        }
    }
}
