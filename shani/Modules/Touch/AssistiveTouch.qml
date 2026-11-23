// Smart touch (after AssistiveTouch / Quick Ball): a floating bubble for
// touchscreens and tablets. Drag it anywhere; tap it and the Ring opens right
// there — Chronoa, Lens, screenshot, media, windows, power under one finger.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    NavWindow {}     // known to the keys-and-controller reach check (Ui.navAuditAll)
    id: win
    visible: Settings.data.assistiveTouch && !Lock.locked && !Ui.ring
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; left: true }
    margins.left: Settings.data.touchX
    margins.top: Settings.data.touchY
    implicitWidth: Theme.px(56)
    implicitHeight: Theme.px(56)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-touch"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function clampToScreen() {
        const sw = win.screen ? win.screen.width : 1920;
        const sh = win.screen ? win.screen.height : 1080;
        const w = win.implicitWidth;
        const h = win.implicitHeight;
        Settings.data.touchX = Math.max(0, Math.min(sw - w, Settings.data.touchX));
        Settings.data.touchY = Math.max(0, Math.min(sh - h, Settings.data.touchY));
    }
    Component.onCompleted: clampToScreen()
    onScreenChanged: clampToScreen()
    onImplicitWidthChanged: clampToScreen()
    onImplicitHeightChanged: clampToScreen()

    Rectangle {
        id: blurCard
        anchors.fill: parent
        radius: width / 2
        color: Theme.alpha(Theme.bg, 0.55)
        border.width: 2
        border.color: Theme.alpha(Theme.accent, 0.8)
        scale: touchArea.pressed && !touchArea.moved ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.mot(80) } }
        Rectangle {
            anchors.centerIn: parent; width: Theme.px(26); height: Theme.px(26); radius: Theme.px(13)
            color: Theme.alpha(Theme.accent, 0.85)
            // three dots say "menu" without depending on a font glyph
            Row {
                anchors.centerIn: parent; spacing: Theme.px(3)
                Rectangle { width: Theme.px(4); height: width; radius: width / 2; color: Theme.accentInk }
                Rectangle { width: Theme.px(4); height: width; radius: width / 2; color: Theme.accentInk }
                Rectangle { width: Theme.px(4); height: width; radius: width / 2; color: Theme.accentInk }
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: Tr.t("Smart touch: open the Ring")
        Accessible.onPressAction: Ui.openRingAt(Settings.data.touchX + win.implicitWidth / 2, Settings.data.touchY + win.implicitHeight / 2)
    }
    MouseArea {
        id: touchArea
        anchors.fill: parent
        property point grab
        property bool moved: false
        onPressed: m => { grab = Qt.point(m.x, m.y); moved = false; }
        onPositionChanged: m => {
            const dx = m.x - grab.x, dy = m.y - grab.y;
            if (Math.abs(dx) + Math.abs(dy) < 6 && !moved)
                return;
            moved = true;
            Settings.data.touchX = Math.max(0, Math.min((win.screen ? win.screen.width : 1920) - win.implicitWidth, Settings.data.touchX + dx));
            Settings.data.touchY = Math.max(0, Math.min((win.screen ? win.screen.height : 1080) - win.implicitHeight, Settings.data.touchY + dy));
        }
        onReleased: if (!moved) Ui.openRingAt(Settings.data.touchX + win.implicitWidth / 2, Settings.data.touchY + win.implicitHeight / 2)
    }
}
