// Smart touch (after AssistiveTouch / Quick Ball): a floating bubble for
// touchscreens and tablets. Drag it anywhere; tap it and the Ring opens right
// there — Chronoa, Lens, screenshot, media, windows, power under one finger.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Settings.data.assistiveTouch && !Lock.locked && !Ui.ring
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; left: true }
    margins.left: Settings.data.touchX
    margins.top: Settings.data.touchY
    implicitWidth: 56
    implicitHeight: 56
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-touch"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.data.blur && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: blurCard
        anchors.fill: parent
        radius: width / 2
        color: Theme.alpha(Theme.bg, 0.55)
        border.width: 2
        border.color: Theme.alpha(Theme.accent, 0.8)
        Rectangle { anchors.centerIn: parent; width: 26; height: 26; radius: 13; color: Theme.alpha(Theme.accent, 0.85) }
        Accessible.role: Accessible.Button
        Accessible.name: Tr.t("Smart touch: open the Ring")
    }
    MouseArea {
        anchors.fill: parent
        property point grab
        property bool moved: false
        onPressed: m => { grab = Qt.point(m.x, m.y); moved = false; }
        onPositionChanged: m => {
            const dx = m.x - grab.x, dy = m.y - grab.y;
            if (Math.abs(dx) + Math.abs(dy) < 6 && !moved)
                return;
            moved = true;
            Settings.data.touchX = Math.max(0, Math.min((win.screen ? win.screen.width : 1920) - 56, Settings.data.touchX + dx));
            Settings.data.touchY = Math.max(0, Math.min((win.screen ? win.screen.height : 1080) - 56, Settings.data.touchY + dy));
        }
        onReleased: if (!moved) Ui.openRingAt(Settings.data.touchX + 28, Settings.data.touchY + 28)
    }
}
