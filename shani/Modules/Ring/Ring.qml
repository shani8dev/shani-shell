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
import "../../Common/Gestures.js" as Hold

PanelWindow {
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    Accessible.role: Accessible.Dialog
    Accessible.name: Tr.t("Ring menu")
    visible: Ui.ring
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-ring"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: disc; radius: disc.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (Ui.ring) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property real radius: Theme.px(132)
    readonly property real dead: 34          // the centre: no slice, closes on click
    property point center: Qt.point(width / 2, height / 2)
    property bool placed: false
    property var stack: []                    // [{ items, center }] for the rings behind this one
    property var items: root()
    onStackChanged: Ui.ringDepth = stack.length
    onItemsChanged: if (hot >= items.length) hot = -1
    property int hot: -1
    readonly property var player: Media.current

    function run(f) {
        Ui.ring = false;
        f();
    }
    function root() {
        const ws = Niri.workspacesOn(Niri.focusedOutput);
        const apps = Settings.data.dockPinned.map(id => DesktopEntries.byId(id)).filter(e => e);
        return [
            // what a touch screen has no keys for (a board opens the Ring from its sides)
            { label: Tr.t("Go"), icon: "go-previous", children: [
                { label: Tr.t("Back"), icon: "go-previous", act: () => Ui.back() },
                { label: Tr.t("Home"), icon: "user-desktop", act: () => Niri.showDesktop() },
                { label: Tr.t("Overview"), icon: "focus-windows", act: () => Niri.action("toggle-overview") },
                { label: Osk.shown ? Tr.t("Hide the keyboard") : Tr.t("Keyboard"), icon: "input-keyboard", act: () => Osk.toggle() }
            ] },
            { label: Tr.t("Chronoa"), icon: "face-smile-big", children: [
                { label: Tr.t("Ask"), icon: "chat-message-new", act: () => Ui.askIsland() },
                { label: Tr.t("Conversation"), icon: "face-smile-big", act: () => Chronoa.open = true },
                // seeing and hearing what is on screen (Lens was a second group with Lens in it twice)
                { label: Tr.t("Lens"), icon: "system-search", act: () => Lens.capture() },
                { label: Tr.t("Read aloud"), icon: "audio-speakers", act: () => Speak.speakSelection() },
                { label: Tr.t("Magnifier"), icon: "zoom-in", act: () => { Ui.closeAll(); Ui.magnifier = true; } },
                { label: Tr.t("Captions"), icon: "media-view-subtitles", act: () => Captions.toggle() }
            ] },
            { label: Tr.t("Screenshot"), icon: "applets-screenshooter", children: [
                { label: Tr.t("Screen"), icon: "video-display", act: () => Niri.action("screenshot-screen") },
                { label: Tr.t("Window"), icon: "focus-windows", act: () => Niri.action("screenshot-window") },
                { label: Tr.t("Region"), icon: "selection-mode", act: () => Niri.action("screenshot") }
            ] },
            { label: Tr.t("Media"), icon: "media-playback-start", children: [
                { label: Tr.t("Play / Pause"), icon: "media-playback-start", act: () => win.player && win.player.togglePlaying() },
                { label: Tr.t("Next"), icon: "media-skip-forward", act: () => win.player && win.player.next() },
                { label: Tr.t("Previous"), icon: "media-skip-backward", act: () => win.player && win.player.previous() },
                { label: Audio.muted ? "Unmute" : "Mute", icon: Audio.muted ? "audio-volume-high" : "audio-volume-muted", act: () => Audio.toggleMute() }
            ] },
            { label: Tr.t("Window"), icon: "focus-windows", children: [
                { label: Tr.t("Close"), icon: "window-close", act: () => Niri.action("close-window") },
                { label: Tr.t("Fullscreen"), icon: "view-fullscreen", act: () => Niri.action("fullscreen-window") },
                { label: Tr.t("Float"), icon: "window-restore", act: () => Niri.action("toggle-window-floating") },
                { label: Tr.t("Maximize"), icon: "window-maximize", act: () => Niri.action("maximize-column") },
                { label: Tr.t("Center"), icon: "zoom-fit-best", act: () => Niri.action("center-column") }
            ] },
            { label: Tr.t("Workspaces"), icon: "view-grid", children: ws.map(w => (
                { label: w.name || ("Workspace " + w.idx), icon: w.is_active ? "object-select" : "view-grid", act: () => Niri.focusWorkspace(w) })) },
            { label: Tr.t("Apps"), icon: "view-app-grid", children: [
                { label: Tr.t("Tools"), icon: "tools", children: [
                    { label: Tr.t("Dictionary"), icon: "accessories-dictionary", act: () => { Ui.closeAll(); Ui.dictionary = true; } },
                    { label: Tr.t("Podcasts"), icon: "audio-headphones", act: () => { Ui.closeAll(); Ui.podcasts = true; } },
                    { label: Tr.t("Network Tools"), icon: "network-workgroup", act: () => { Ui.closeAll(); Ui.netTools = true; } },
                    { label: Tr.t("Nearby Share"), icon: "network-wireless", act: () => { Ui.closeAll(); Ui.nearby = true; } },
                    { label: Tr.t("All tools…"), icon: "system-search", act: () => Ui.toggleLauncher("tool:") }
                ] }
            ].concat(apps.slice(0, 8).map(e => (
                { label: e.name, app: e.icon, act: () => Launch.app(e.id) }))) },
            { label: Tr.t("Power"), icon: "system-shutdown", children: [
                { label: Tr.t("Lock"), icon: "system-lock-screen", act: () => Lock.lock() },
                { label: Tr.t("Suspend"), icon: "weather-clear-night", act: () => Power.suspend() },
                { label: Tr.t("Log out"), icon: "system-log-out", act: () => Power.logout() }
            ] }
        ].filter(it => it.act || (it.children && it.children.length > 0));
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
    function moveHot(step) {
        if (items.length === 0)
            return;
        hot = hot < 0 ? (step > 0 ? 0 : items.length - 1)
                      : (hot + step + items.length) % items.length;
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
            hot = -1;
            placed = Ui.ringAt.x >= 0;
            center = placed ? Qt.point(Math.max(radius + 20, Math.min(width - radius - 20, Ui.ringAt.x)),
                                       Math.max(radius + 20, Math.min(height - radius - 20, Ui.ringAt.y)))
                            : Qt.point(width / 2, height / 2);
            Ui.ringAt = Qt.point(-1, -1);
            keys.forceActiveFocus();
        } else {
            dwell.stop();               // a pending dwell must not act after dismissal
            stack = [];                 // ringDepth must not outlive the ring
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.back()
        // 1..8 pick a slice by number; arrows move the highlight, Enter/Space acts
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Left || e.key === Qt.Key_Up) {
                win.moveHot(-1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down) {
                win.moveHot(1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                if (win.hot >= 0)
                    win.choose(win.hot);
                e.accepted = true;
            } else {
                const n = e.key - Qt.Key_1;
                if (n >= 0 && n < win.items.length)
                    win.choose(n);
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // a finger has no right button: a long press goes back
        property var held: Hold.state()
        onPressed: Hold.press(held)
        onPressAndHold: Hold.hold(held)
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
            if (Hold.swallowed(held) || m.button === Qt.RightButton)
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
            if (!win.visible)
                return;
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
        Behavior on scale { NumberAnimation { duration: Theme.mot(140); easing.type: Easing.OutBack } }
        Behavior on x { NumberAnimation { duration: Theme.mot(160); easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Theme.mot(160); easing.type: Easing.OutCubic } }

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
                // nothing pointed at yet: say how it works, not an empty hole
                text: win.hot >= 0 && win.items[win.hot] ? win.items[win.hot].label : (win.stack.length > 0 ? Tr.t("Back") : Tr.t("Point at one to see what it does · Esc closes"))
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
                font.weight: win.hot >= 0 ? Font.DemiBold : Font.Normal
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
            Accessible.role: Accessible.Button
            Accessible.name: (modelData.label || "")
                + (modelData.children ? ", " + Tr.t("submenu") : "")
            Accessible.focused: isHot
            Accessible.onPressAction: win.choose(index)
            x: at.x - width / 2
            y: at.y - height / 2
            width: isHot ? 64 : 54
            height: width
            radius: width / 2
            color: isHot ? Theme.accent : Theme.hover
            border.width: modelData.children ? 1 : 0
            border.color: isHot ? Theme.accentInk : Theme.accentLine
            Behavior on width { NumberAnimation { duration: Theme.mot(110) } }
            Behavior on x { NumberAnimation { duration: Theme.mot(160); easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Theme.mot(160); easing.type: Easing.OutCubic } }

            Icon {
                visible: !slice.modelData.app
                anchors.centerIn: parent
                name: slice.modelData.icon || ""
                size: Theme.px(22)
                color: slice.isHot ? Theme.accentInk : Theme.text
            }
            IconImage {
                visible: !!slice.modelData.app
                anchors.centerIn: parent
                implicitSize: 30
                source: AppIconPath.pathFor(slice.modelData.app, "application-x-executable")
            }
            // a dot on slices that open a ring of their own
            Rectangle {
                visible: !!slice.modelData.children
                width: Theme.px(6)
                height: Theme.px(6)
                radius: Theme.px(3)
                color: slice.isHot ? Theme.accentInk : Theme.accent
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.px(5)
            }
        }
    }
}
