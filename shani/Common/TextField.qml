// A single-line input on a glass well; `secret` masks it.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property alias text: input.text
    property alias input: input
    // callers that fill the pad from the history move the caret directly
    property alias cursorPosition: input.cursorPosition
    property alias selectionStart: input.selectionStart
    property alias selectionEnd: input.selectionEnd
    function insert(position, value) { input.insert(position, value) }
    function remove(position, length) { input.remove(position, length) }
    property alias readOnly: input.readOnly
    property string placeholder
    // the same thing under Qt's own name, so a panel written against
    // QtQuick.Controls' TextField works here unchanged
    property alias placeholderText: root.placeholder
    property string label: ""          // what a screen reader calls it; the placeholder when empty
    property bool secret: false
    // "" (default) | "digits" | "email" | "url": the OSK's input hints
    property string mode: ""
    // Ananta's PasswordField: a long secret is impossible to check for typos
    // when it is always masked, so a secret field carries a show/hide eye.
    property bool revealed: false
    // a one-line reason shown under the field, in red, when the value is wrong
    property string error: ""
    signal accepted()

    implicitHeight: Math.max(Theme.px(38), Theme.touchTarget) + (root.error !== "" ? Theme.px(16) : 0)
    radius: Theme.radiusSmall
    color: Theme.surface1
    border.width: 1
    border.color: root.error !== "" ? Theme.danger : (input.activeFocus ? Theme.accent : Theme.stroke)
    Accessible.description: root.error

    Text { id: a11yLabel; text: root.label || root.placeholder; opacity: 0; width: 0; height: 0; Accessible.name: text }
    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Theme.px(12)
        anchors.rightMargin: Theme.px(12) + (root.secret ? Theme.px(34) : 0)
        anchors.bottomMargin: root.error !== "" ? Theme.px(16) : 0
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.accent
        font.family: Theme.font
        font.pixelSize: Theme.type("body")
        // Inter's bullet is wider than its advance, so a masked value renders as
        // one solid bar; tracking separates the dots again
        font.letterSpacing: input.echoMode === TextInput.Password && input.text !== "" ? 1.5 : 0
        echoMode: root.secret && !root.revealed ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        inputMethodHints: root.secret ? (Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase) : (root.mode === "digits" ? Qt.ImhDigitsOnly : root.mode === "email" ? Qt.ImhEmailCharactersOnly : root.mode === "url" ? Qt.ImhUrlCharactersOnly : Qt.ImhNone)
        Accessible.role: Accessible.EditableText
        Accessible.name: root.label || root.placeholder
        // Qt gives a password field no accessible name at all (measured, Qt 6.12:
        // whatever is set, AT-SPI reads ''), so a password field is labelled by
        // a named, unseen label instead - Orca reads that relation. Kept for
        // every field: an always-present labelledBy avoids the null warning.
        Accessible.labelledBy: a11yLabel
        clip: true
        activeFocusOnTab: root.enabled && !root.readOnly   // in the tab chain: Tab, the arrows and a controller's d-pad reach it
        onAccepted: root.accepted()
        onActiveFocusChanged: Ui.trackTextInput(input, activeFocus && !readOnly)
        onReadOnlyChanged: Ui.trackTextInput(input, activeFocus && !readOnly)
        Component.onDestruction: Ui.trackTextInput(input, false)
        // OK on an EMPTY field: the screen keyboard, typed from a remote (as a
        // TV does). With text in it, Enter submits as always.
        Keys.onReturnPressed: e => { e.accepted = input.text === "" && !root.readOnly; if (e.accepted) Ui.typingRequested(); }
        Keys.onEnterPressed: e => { e.accepted = input.text === "" && !root.readOnly; if (e.accepted) Ui.typingRequested(); }
        // a field is one line: Down / Up go on to the next / previous control, as in a list
        Keys.onDownPressed: { const n = input.nextItemInFocusChain(true); if (n) { Ui.keyMovedAt = Date.now(); n.forceActiveFocus(Qt.TabFocusReason); } }
        Keys.onUpPressed: { const n = input.nextItemInFocusChain(false); if (n) { Ui.keyMovedAt = Date.now(); n.forceActiveFocus(Qt.BacktabFocusReason); } }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: root.placeholder
            color: Theme.faint
            font: input.font
        }
    }

    Item {
        visible: root.secret
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(4)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.px(30)
        height: parent.height
        Icon {
            anchors.centerIn: parent
            name: root.revealed ? "view-conceal" : "view-reveal"
            size: Theme.px(16)
            color: Theme.dim
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.revealed = !root.revealed
        }
        Accessible.role: Accessible.Button
        Accessible.name: root.revealed ? Tr.t("Hide secret") : Tr.t("Show secret")
        Accessible.onPressAction: root.revealed = !root.revealed
        KeyFocus { onActivated: root.revealed = !root.revealed }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Theme.px(2)
        visible: root.error !== ""
        color: Theme.danger
    }
    Text {
        // the field reserves a 16px strip by lifting `input`; put the message
        // in that strip, not below the field where it overlaps the next label
        anchors { left: parent.left; right: parent.right; top: input.bottom; topMargin: Theme.px(2) }
        visible: root.error !== ""
        text: root.error
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.type("caption")
    }
}
