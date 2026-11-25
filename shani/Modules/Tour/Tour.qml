// The first-login tour: five cards on what this desktop has that others do
// not, each with its key, and a last one to make it yours (layout, wallpaper,
// light or dark). Once per account (Settings.tourSeen); skippable;
// again from the launcher ("Tour"). Keyboard: Enter / → next, Esc skips.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    readonly property bool auto: Settings.loaded && !Settings.data.tourSeen && !Quickshell.env("SHANI_NO_TOUR")
    // a password prompt (polkit) comes first: the tour holds the keyboard, and on a
    // fresh account the prompt typed into the tour instead (polkit-test caught it)
    visible: (auto || Ui.tour) && !Lock.locked && !Polkit.active
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.alpha("#000000", 0.45)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-tour"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: blurCard; radius: blurCard.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (visible) && !Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property int step: 0
    readonly property var cards: [
        { icon: "system-search", title: Tr.t("One place to start anything"), body: "Super+Space opens the launcher: apps, files, settings, sums (12*12), emoji, clipboard history (c …). Start with ? to ask Chronoa instead.", keys: "Super + Space" },
        { icon: "face-smile-big", title: Tr.t("Meet Chronoa, in the Island"), body: "The pill in the middle of the bar is your assistant. Click it or press Super+A, and ask in your own words — it can act on your computer, and asks before anything that matters. While it is idle, the Island shows what is going on: a timer, music, a recording.", keys: "Super + A" },
        { icon: "preferences-system", title: Tr.t("Quick settings"), body: "Click the clock or press Super+, for Wi-Fi, Bluetooth, sound, Do Not Disturb and night light, your notifications, and Settings. All tiles shows the rest.", keys: "Super + ," },
        { icon: "focus-windows", title: Tr.t("Windows sit side by side"), body: "New windows open beside the others and the row scrolls: Super+← → to move along, Super+O for every workspace at once. On a touchpad: three fingers to move, four fingers up for the overview. Super+M minimises a window to the dock and Super+D shows the desktop, as on Windows. Super+Shift+/ lists every shortcut.", keys: "Super + M   ·   Super + D   ·   Super + O" , shortcuts: true },
        { icon: "input-keyboard", title: Tr.t("Coming from another computer?"), body: "Most keys are where you know them: Super+E files, Super+L lock, Super+D the desktop, Super+V clipboard history, Super+. emoji, Super+I Settings, Super+Z window layouts. Three are the assistant's first: Super+A asks Chronoa (quick settings are Super+,), Super+S is Lens (search everything with Super+Space), and the next input method is Super+Shift+I. Settings > Screen and layout has familiar layouts too: a taskbar along the bottom, or a launcher down the left.", keys: "Super + I   ·   Super + ,   ·   Super + Shift + I" },
        { icon: "zoom-in", title: Tr.t("Lens and the Ring"), body: "Super+S: select any part of the screen to read its text, scan a code, or ask Chronoa about it. Super+X: the Ring, a pie of the things you do most, right under the pointer.", keys: "Super + S   ·   Super + X" },
        // the last card: not a key to learn but the desktop to make your own, right here
        { icon: "view-grid", title: Tr.t("Make it yours"), body: Tr.t("Choose how your desktop is laid out — each layout is shown as a picture, and you can try one on before keeping it. Then a wallpaper and colours you like. All of it can be changed again any time in Settings > Personalisation."), keys: "", choices: true }
    ]
    function finish() {
        Settings.data.tourSeen = true;
        Ui.tour = false;
        step = 0;
    }
    function next() { step < cards.length - 1 ? step++ : finish(); }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: win.finish()
        Keys.onReturnPressed: win.next()
        Keys.onRightPressed: win.next()
        Keys.onLeftPressed: if (win.step > 0) win.step--
    }
    Glass {
        id: blurCard
        Accessible.role: Accessible.Dialog
        Accessible.name: win.cards[win.step].title
        Accessible.description: Tr.t("Step %1 of %2").arg(win.step + 1).arg(win.cards.length)
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 48)
        implicitHeight: col.implicitHeight + 48
        strong: true
        radius: Theme.radiusLarge
        ColumnLayout {
            id: col
            x: 24
            y: 24
            width: parent.width - 48
            spacing: Theme.px(14)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Theme.px(64)
                implicitHeight: Theme.px(64)
                radius: Theme.px(20)
                color: Theme.accentSoft
                Icon { anchors.centerIn: parent; name: win.cards[win.step].icon; size: Theme.px(34); color: Theme.accent }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: win.cards[win.step].title
                color: Theme.text
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(20) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: win.cards[win.step].body
                color: Theme.dim
                wrapMode: Text.Wrap
                lineHeight: 1.15
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }
            Rectangle {
                visible: win.cards[win.step].keys !== ""
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: keys.implicitWidth + 20
                implicitHeight: Theme.px(28)
                radius: Theme.px(8)
                color: Theme.hover
                border.color: Theme.stroke
                Text { id: keys; anchors.centerIn: parent; text: win.cards[win.step].keys; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.px(12) * Theme.fontScale }
            }
            // "Make it yours": each opens the place to do it, the tour stays done
            Flow {
                visible: !!win.cards[win.step].choices
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Button { kind: "outline"; text: Tr.t("Screen and layout…"); onClicked: { win.finish(); Ui.layoutSwitcher = true; } }
                Button { kind: "outline"; text: Tr.t("Wallpaper & colours…"); onClicked: { win.finish(); Ui.openSettings("personal"); } }
                Button { kind: "outline"; text: Settings.data.darkMode ? Tr.t("Try the light style") : Tr.t("Try the dark style"); onClicked: Settings.data.darkMode = !Settings.data.darkMode }
            }
            RowLayout {
                Layout.fillWidth: true
                Row {
                    spacing: Theme.px(6)
                    Repeater {
                        model: win.cards.length
                        Rectangle {
                            required property int index
                            width: index === win.step ? 18 : 7
                            height: Theme.px(7)
                            radius: Theme.px(4)
                            color: index <= win.step ? Theme.accent : Theme.stroke
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                // pointer and touch users have no Left key to go back with
                Button { text: Tr.t("Back"); visible: win.step > 0; onClicked: if (win.step > 0) win.step-- }
                Button { text: Tr.t("Skip"); visible: win.step < win.cards.length - 1; onClicked: win.finish() }
                // the windows card: every key, in niri's own list
                Button { visible: !!win.cards[win.step].shortcuts; text: Tr.t("All keyboard shortcuts"); onClicked: { win.finish(); Niri.action("show-hotkey-overlay"); } }
                Button { kind: "primary"; text: win.step < win.cards.length - 1 ? Tr.t("Next") : Tr.t("Start"); onClicked: win.next() }
            }
        }
    }
}
