// Teleprompter: paste a script and read it at your own pace. Text is held in
// this window (no new service or bridge): paste from the clipboard or type in
// the script area, then play. The timer scrolls the view a fixed distance per
// tick, so speed is in pixels per second and does not depend on the frame rate.
// Space plays/pauses and + / - change speed when the script is not being typed
// in (typing a hyphen in a script must not change the speed).
// Keyboard: Space play/pause, + / - speed, Home / End jump, Esc close.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Teleprompter"
    visible: Ui.teleprompter
    onGone: Ui.teleprompter = false
    // a Present action (editor, notes or translator) leaves its text on the
    // clipboard; take it when the window opens. The clipboard is left intact —
    // it belongs to the person, not to this window.
    onVisibleChanged: if (visible) win.prefillFromClipboard()
    implicitWidth: Theme.px(900)
    implicitHeight: Theme.px(640)

    // the largest script we will hold: a bigger paste is refused with a reason,
    // rather than making the text layout hang the shell
    readonly property int maxChars: 500000
    property string text: ""
    property real speed: 60            // pixels per second
    property real fontSize: Settings.data.textEditorFontSize || 22
    property bool playing: false
    property bool reverse: false       // false: scroll down, true: scroll up
    property string error: ""

    readonly property real maxScroll: Math.max(0, view.contentHeight - view.height)
    readonly property bool atStart: view.contentY <= 0.5
    readonly property bool atEnd: view.contentY >= win.maxScroll - 0.5
    readonly property int charCount: win.text.length
    readonly property int wordCount: win.countWords(win.text)

    function countWords(s) {
        const m = String(s || "").trim().match(/\S+/g);
        return m ? m.length : 0;
    }
    function setSpeed(delta) { win.speed = Math.max(10, Math.min(400, win.speed + delta)); }
    function setFontSize(delta) { win.fontSize = Math.max(10, Math.min(72, win.fontSize + delta)); }
    function togglePlay() {
        if (win.text.trim() === "") { win.error = "Paste a script first"; return; }
        win.error = "";
        win.playing = !win.playing;
    }
    function jumpStart() { view.contentY = 0; }
    function jumpEnd() { view.contentY = win.maxScroll; }
    function scrollStep() {
        const max = win.maxScroll;
        if (max <= 0) { win.playing = false; return; }
        const step = win.speed * scrollTick.interval / 1000 * (win.reverse ? -1 : 1);
        let y = view.contentY + step;
        if (y <= 0) { y = 0; win.playing = false; }
        else if (y >= max) { y = max; win.playing = false; }
        view.contentY = y;
    }
    function paste() {
        const s = String(Quickshell.clipboardText || "");
        if (s.trim() === "") { win.error = "The clipboard is empty"; return; }
        if (s.length > win.maxChars) { win.error = "That is too much text (500,000 characters max)"; return; }
        win.error = "";
        win.playing = false;
        win.text = s;
        edit.cursorPosition = 0;
        view.contentY = 0;
    }
    function prefillFromClipboard() {
        const s = String(Quickshell.clipboardText || "");
        if (s.trim() === "") return;
        win.paste();
    }
    // shortcut: TranslateWindow does not read a clipboard handoff, so only copy the
    // first line — no Ui.translate flag; upgrade when TranslateWindow reads it
    function copyFirstLineForTranslation() {
        const first = String(win.text).split("\n")[0].trim();
        if (first === "") return;
        Quickshell.clipboardText = first;
    }
    function dismissError() { win.error = ""; }
    function shortcut(e) {
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false;
        const typing = edit.activeFocus;
        if (e.key === Qt.Key_Space && !typing) { win.togglePlay(); e.accepted = true; return true; }
        if (!typing && (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)) { win.setSpeed(10); e.accepted = true; return true; }
        if (!typing && e.key === Qt.Key_Minus) { win.setSpeed(-10); e.accepted = true; return true; }
        if (e.key === Qt.Key_Home) { win.jumpStart(); e.accepted = true; return true; }
        if (e.key === Qt.Key_End) { win.jumpEnd(); e.accepted = true; return true; }
        return false;
    }

    tools: [
        IconButton {
            icon: win.playing ? "media-playback-pause" : "media-playback-start"
            tip: (win.playing ? "Pause" : "Play") + " (Space)"
            accessibleName: win.playing ? "Pause scrolling" : "Play scrolling"
            size: Theme.px(30)
            on: win.playing
            onClicked: win.togglePlay()
        },
        IconButton { icon: "go-first"; tip: "Jump to start (Home)"; accessibleName: "Jump to start"; size: Theme.px(30); onClicked: win.jumpStart() },
        IconButton { icon: "go-last"; tip: "Jump to end (End)"; accessibleName: "Jump to end"; size: Theme.px(30); onClicked: win.jumpEnd() },
        Button { text: "Reverse"; flat: true; checked: win.reverse; onClicked: win.reverse = !win.reverse },
        Button { text: "Paste"; flat: true; onClicked: win.paste() },
        Button {
            text: "Copy first line for translation"
            Accessible.description: "Copies the first line to the clipboard for translation"
            flat: true
            enabled: win.text.trim() !== ""
            onClicked: win.copyFirstLineForTranslation()
        },
        IconButton { icon: "zoom-out"; tip: "Smaller text"; accessibleName: "Smaller text"; size: Theme.px(30); onClicked: win.setFontSize(-2) },
        IconButton { icon: "zoom-in"; tip: "Larger text"; accessibleName: "Larger text"; size: Theme.px(30); onClicked: win.setFontSize(2) }
    ]

    Timer {
        id: scrollTick
        interval: 40
        repeat: true
        running: win.playing && win.visible && win.text !== ""
        onTriggered: win.scrollStep()
    }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onPressed: e => { if (win.shortcut(e)) e.accepted = true; }
        Keys.onEscapePressed: Ui.teleprompter = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(8)

            // a failed paste is a state with its own way out
            RowLayout {
                Layout.fillWidth: true
                visible: win.error !== ""
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    text: win.error
                    color: Theme.danger
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Button { text: "Dismiss"; flat: true; onClicked: win.dismissError() }
            }

            EmptyState {
                visible: win.text.trim() === ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon: "edit-paste"
                title: "No script yet"
                subtitle: "Paste text from the clipboard, or type it below, then press Play"
                actionText: "Paste from clipboard"
                onAction: win.paste()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.text.trim() !== ""
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                clip: true

                Flickable {
                    id: view
                    anchors.fill: parent
                    anchors.margins: Theme.px(12)
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(edit.implicitHeight + Theme.px(12), height)
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: edit
                        width: view.width
                        text: win.text
                        readOnly: win.playing
                        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                        color: Theme.text
                        selectionColor: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.px(win.fontSize) * Theme.fontScale
                        Accessible.name: "Teleprompter script"
                        Accessible.role: Accessible.EditableText
                        onTextChanged: { if (win.text !== text) win.text = text; }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    text: win.wordCount + " words · " + win.charCount + " characters"
                          + (win.reverse ? " · scrolling up" : " · scrolling down")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                IconButton {
                    icon: "zoom-out"; tip: "Slower (-)"; accessibleName: "Slower"
                    size: Theme.px(26); onClicked: win.setSpeed(-10)
                }
                Text {
                    text: Math.round(win.speed) + " px/s"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                IconButton {
                    icon: "zoom-in"; tip: "Faster (+)"; accessibleName: "Faster"
                    size: Theme.px(26); onClicked: win.setSpeed(10)
                }
                Text {
                    text: "Space play · + / - speed · Home / End jump"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }
        }
    }
}
