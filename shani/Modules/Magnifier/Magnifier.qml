// The magnifier (zoom): a round loupe over a frozen frame of the screen,
// following the pointer. Scroll changes the power (1.5x – 6x), right-click
// takes a fresh frame, Esc or a click closes it. Frozen, because a live capture
// would include the loupe itself and magnify it without end — niri has no
// full-screen zoom of its own for the shell to drive.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.Common
import qs.Services
import "../../Common/Gestures.js" as Hold

PanelWindow {
    id: win
    visible: Ui.magnifier && ready && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-magnifier"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Accessible.role: Accessible.Window
    Accessible.name: Tr.t("Magnifier %1×").arg(win.zoom.toFixed(1))

    property real zoom: 2.5
    property point at: Qt.point(width / 2, height / 2)
    readonly property real size: Theme.px(320)

    function clampAt(p) {
        return Qt.point(Math.max(0, Math.min(width, p.x)), Math.max(0, Math.min(height, p.y)));
    }

    // the frame comes from grim, taken before the window maps (Ui.magnifier
    // flips on once it is written) — Quickshell's ScreencopyView needs dmabuf
    // feedback v4, which not every compositor offers
    readonly property string path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-magnifier.png"
    property int shot: 0
    property bool ready: false          // hidden while grim takes the frame, so the loupe is not in it
    function grab() { ready = false; snap.running = true; }
    Process {
        id: snap
        command: ["grim", "-o", win.screen ? win.screen.name : "", win.path]
        onExited: code => {
            if (code === 0) { win.shot++; win.ready = true; }
            else Ui.magnifier = false;
        }
    }
    Connections {
        target: Ui
        function onMagnifierChanged() { if (Ui.magnifier) win.grab(); }
    }
    Connections {
        target: Lock
        function onLockedChanged() { if (Lock.locked) Ui.magnifier = false; }
    }
    onVisibleChanged: if (visible) { keys.forceActiveFocus(); win.at = win.clampAt(win.at); }
    onWidthChanged: win.at = win.clampAt(win.at)
    onHeightChanged: win.at = win.clampAt(win.at)
    // made when opened (shell.qml's LazyLoader): the first frame is taken now
    Component.onCompleted: if (Ui.magnifier) grab()

    // the frame, full size, not shown: the loupe draws a magnified part of it
    Image {
        id: frame
        visible: false
        width: win.width
        height: win.height
        source: win.shot > 0 ? "file://" + win.path + "?" + win.shot : ""
        cache: false
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.magnifier = false
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) win.zoom = Math.min(6, win.zoom + 0.5);
            else if (e.key === Qt.Key_Minus) win.zoom = Math.max(1.5, win.zoom - 0.5);
            else if (e.key === Qt.Key_R) win.grab();   // keyboard equivalent of the fresh-frame right-click
        }
    }
    MouseArea {
        objectName: "nav:pointer"          // the lens follows the pointer: a pad's right stick
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // a finger has no right button: a long press takes the grab
        property var held: Hold.state()
        onPressed: Hold.press(held)
        onPressAndHold: Hold.hold(held)
        onPositionChanged: m => win.at = win.clampAt(Qt.point(m.x, m.y))
        onWheel: w => {
            if (w.angleDelta.y === 0) return;   // a horizontal-only scroll is not a zoom
            win.zoom = Math.max(1.5, Math.min(6, win.zoom + (w.angleDelta.y > 0 ? 0.5 : -0.5)));
        }
        onClicked: m => (Hold.swallowed(held) || m.button === Qt.RightButton) ? win.grab() : (Ui.magnifier = false)
    }

    ClippingRectangle {
        x: win.at.x - win.size / 2
        y: win.at.y - win.size / 2
        width: win.size
        height: win.size
        radius: win.size / 2
        color: Theme.bg
        border.width: 3
        border.color: Theme.accent
        ShaderEffectSource {
            sourceItem: frame
            x: -(win.at.x * win.zoom - win.size / 2)
            y: -(win.at.y * win.zoom - win.size / 2)
            width: win.width * win.zoom
            height: win.height * win.zoom
            smooth: true
            live: true
        }
    }
    Glass {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(100)   // clear the dock's step-aside hint
        width: hint.implicitWidth + 32
        height: Theme.px(34)
        strong: true
        Text {
            id: hint
            anchors.centerIn: parent
            text: Tr.t("Magnifier %1×  ·  scroll to zoom  ·  R / right-click: fresh frame  ·  Esc to close").arg(win.zoom.toFixed(1))
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
    }
}
