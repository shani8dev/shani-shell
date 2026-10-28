// The Ring: a pie menu at the pointer (after Kando and marking menus).
// Mod+X opens it where the pointer is; moving toward a slice highlights it and
// a click acts. Rest on a slice with children and its own ring opens there;
// right-click or Esc steps back. Direction, not distance, picks the slice, so
// a practised hand flicks without looking.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.ring
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-ring"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Ui.ring ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property real radius: 132
    readonly property real dead: 34          // the centre: no slice, closes on click
    property point center: Qt.point(width / 2, height / 2)
    property bool placed: false
    property var stack: []                    // [{ items, center }] for the rings behind this one
    property var items: root()
    onStackChanged: Ui.ringDepth = stack.length
    property int hot: -1
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null

    function run(f) {
        Ui.ring = false;
        f();
    }
    function root() {
        const ws = Niri.workspacesOn(Niri.focusedOutput);
        const apps = Settings.data.dockPinned.map(id => DesktopEntries.byId(id)).filter(e => e);
        return [
            { label: "Chronoa", icon: "face-smile-big", children: [
                { label: "Ask", icon: "chat-message-new", act: () => Ui.askIsland() },
                { label: "Conversation", icon: "face-smile-big", act: () => Chronoa.open = true },
                { label: "Lens", icon: "system-search", act: () => Lens.capture() }
            ] },
            { label: "Lens", icon: "system-search", act: () => Lens.capture() },
            { label: "Screenshot", icon: "applets-screenshooter", children: [
                { label: "Screen", icon: "video-display", act: () => Niri.action("screenshot-screen") },
                { label: "Window", icon: "focus-windows", act: () => Niri.action("screenshot-window") },
                { label: "Region", icon: "selection-mode", act: () => Niri.action("screenshot") }
            ] },
            { label: "Media", icon: "media-playback-start", children: [
                { label: "Play / Pause", icon: "media-playback-start", act: () => win.player && win.player.togglePlaying() },
                { label: "Next", icon: "media-skip-forward", act: () => win.player && win.player.next() },
                { label: "Previous", icon: "media-skip-backward", act: () => win.player && win.player.previous() },
                { label: Audio.muted ? "Unmute" : "Mute", icon: Audio.muted ? "audio-volume-high" : "audio-volume-muted", act: () => Audio.toggleMute() }
            ] },
            { label: "Window", icon: "focus-windows", children: [
                { label: "Close", icon: "window-close", act: () => Niri.action("close-window") },
                { label: "Fullscreen", icon: "view-fullscreen", act: () => Niri.action("fullscreen-window") },
                { label: "Float", icon: "window-restore", act: () => Niri.action("toggle-window-floating") },
                { label: "Maximize", icon: "window-maximize", act: () => Niri.action("maximize-column") },
                { label: "Center", icon: "zoom-fit-best", act: () => Niri.action("center-column") }
            ] },
            { label: "Workspaces", icon: "view-grid", children: ws.map(w => (
                { label: w.name || ("Workspace " + w.idx), icon: w.is_active ? "object-select" : "view-grid", act: () => Niri.focusWorkspace(w) })) },
            { label: "Apps", icon: "view-app-grid", children: apps.slice(0, 8).map(e => (
                { label: e.name, app: e.icon, act: () => e.execute() })) },
            { label: "Power", icon: "system-shutdown", children: [
                { label: "Lock", icon: "system-lock-screen", act: () => Lock.lock() },
                { label: "Suspend", icon: "weather-clear-night", act: () => Power.suspend() },
                { label: "Log out", icon: "system-log-out", act: () => Power.logout() }
            ] }
        ];
    }

    function sliceAt(x, y) {
        const dx = x - center.x, dy = y - center.y;
        if (Math.hypot(dx, dy) < dead || items.length === 0)
            return -1;
        // slice 0 points straight up, the rest follow clockwise
        let a = Math.atan2(dx, -dy);
        if (a < 0)
            a += 2 * Math.PI;
        const step = 2 * Math.PI / items.length;
        return Math.floor((a + step / 2) / step) % items.length;
    }
    function slicePos(i, r) {
        const a = i * 2 * Math.PI / items.length;
        return Qt.point(center.x + Math.sin(a) * r, center.y - Math.cos(a) * r);
    }
    function choose(i) {
        const it = items[i];
        if (!it)
            return;
        if (it.children && it.children.length > 0) {
            const p = slicePos(i, radius * 0.9);
            stack = stack.concat([{ items: items, center: center }]);
            items = it.children;
            center = Qt.point(Math.max(radius + 20, Math.min(width - radius - 20, p.x)),
                              Math.max(radius + 20, Math.min(height - radius - 20, p.y)));
            hot = -1;
        } else if (it.act) {
            run(it.act);
        }
    }
    function back() {
        if (stack.length === 0) {
            Ui.ring = false;
            return;
        }
        const prev = stack[stack.length - 1];
        stack = stack.slice(0, -1);
        items = prev.items;
        center = prev.center;
        hot = -1;
    }

    onVisibleChanged: {
        if (visible) {
            stack = [];
            items = root();
            placed = false;
            hot = -1;
            center = Qt.point(width / 2, height / 2);
            keys.forceActiveFocus();
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.back()
        // 1..8 pick a slice by number, for keyboard use
        Keys.onPressed: e => {
            const n = e.key - Qt.Key_1;
            if (n >= 0 && n < win.items.length)
                win.choose(n);
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPositionChanged: m => {
            // the first position we learn is where the pointer was: open there
            if (!win.placed) {
                win.placed = true;
                win.center = Qt.point(Math.max(win.radius + 20, Math.min(win.width - win.radius - 20, m.x)),
                                      Math.max(win.radius + 20, Math.min(win.height - win.radius - 20, m.y)));
                return;
            }
            win.hot = win.sliceAt(m.x, m.y);
            dwell.restart();
        }
        onClicked: m => {
            if (m.button === Qt.RightButton)
                win.back();
            else if (win.sliceAt(m.x, m.y) < 0)
                win.back();
            else
                win.choose(win.sliceAt(m.x, m.y));
        }
    }

    // resting on a slice with children opens its ring
    Timer {
        id: dwell
        interval: 420
        onTriggered: {
            const it = win.items[win.hot];
            if (it && it.children && it.children.length > 0)
                win.choose(win.hot);
        }
    }

    // ---- drawing ----------------------------------------------------------
    Rectangle {
        id: disc
        x: win.center.x - width / 2
        y: win.center.y - height / 2
        width: win.radius * 2 + 64
        height: width
        radius: width / 2
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.stroke
        scale: win.visible ? 1 : 0.6
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // the centre: what the highlighted slice is
        Rectangle {
            anchors.centerIn: parent
            width: win.dead * 2 + 40
            height: width
            radius: width / 2
            color: Theme.alpha(Theme.bg, 0.6)
            border.width: 1
            border.color: win.hot >= 0 ? Theme.accentLine : Theme.stroke
            Text {
                anchors.centerIn: parent
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: win.hot >= 0 && win.items[win.hot] ? win.items[win.hot].label : (win.stack.length > 0 ? "back" : "")
                color: win.hot >= 0 ? Theme.text : Theme.faint
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
    }

    Repeater {
        model: win.items
        Rectangle {
            id: slice
            required property var modelData
            required property int index
            readonly property point at: win.slicePos(index, win.radius)
            readonly property bool isHot: win.hot === index
            x: at.x - width / 2
            y: at.y - height / 2
            width: isHot ? 64 : 54
            height: width
            radius: width / 2
            color: isHot ? Theme.accent : Theme.hover
            border.width: modelData.children ? 1 : 0
            border.color: isHot ? Theme.accentInk : Theme.accentLine
            Behavior on width { NumberAnimation { duration: 110 } }
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Icon {
                visible: !slice.modelData.app
                anchors.centerIn: parent
                name: slice.modelData.icon || ""
                size: 22
                color: slice.isHot ? Theme.accentInk : Theme.text
            }
            IconImage {
                visible: !!slice.modelData.app
                anchors.centerIn: parent
                implicitSize: 30
                source: slice.modelData.app ? Quickshell.iconPath(slice.modelData.app, "application-x-executable") : ""
            }
            // a dot on slices that open a ring of their own
            Rectangle {
                visible: !!slice.modelData.children
                width: 6
                height: 6
                radius: 3
                color: slice.isHot ? Theme.accentInk : Theme.accent
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
            }
        }
    }
}
