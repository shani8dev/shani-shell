// A single-line input on a glass well; `secret` masks it.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property alias text: input.text
    property alias input: input
    property alias readOnly: input.readOnly
    property string placeholder
    // the same thing under Qt's own name, so a panel written against
    // QtQuick.Controls' TextField works here unchanged
    property alias placeholderText: root.placeholder
    property string label: ""          // what a screen reader calls it; the placeholder when empty
    property bool secret: false
    signal accepted()

    implicitHeight: Math.max(Theme.px(38), Theme.touchTarget)
    radius: Theme.radiusSmall
    color: Theme.surface1
    border.width: 1
    border.color: input.activeFocus ? Theme.accent : Theme.stroke

    Text { id: a11yLabel; text: root.label || root.placeholder; opacity: 0; width: 0; height: 0; Accessible.name: text }
    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Theme.px(12)
        anchors.rightMargin: Theme.px(12)
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.accent
        font.family: Theme.font
        font.pixelSize: Theme.px(13) * Theme.fontScale
        echoMode: root.secret ? TextInput.Password : TextInput.Normal
        Accessible.role: Accessible.EditableText
        Accessible.name: root.label || root.placeholder
        // Qt gives a password field no accessible name at all (measured, Qt 6.12:
        // whatever is set, AT-SPI reads ''), so a password field is labelled by
        // a named, unseen label instead - Orca reads that relation. Kept for
        // every field: an always-present labelledBy avoids the null warning.
        Accessible.labelledBy: a11yLabel
        clip: true
        onAccepted: root.accepted()
        onActiveFocusChanged: Ui.trackTextInput(input, activeFocus && !readOnly)
        onReadOnlyChanged: Ui.trackTextInput(input, activeFocus && !readOnly)
        Component.onDestruction: Ui.trackTextInput(input, false)
        // OK on an EMPTY field: the screen keyboard, typed from a remote (as a
        // TV does). With text in it, Enter submits as always.
        Keys.onReturnPressed: e => { e.accepted = input.text === "" && !root.readOnly; if (e.accepted) Ui.typingRequested(); }
        Keys.onEnterPressed: e => { e.accepted = input.text === "" && !root.readOnly; if (e.accepted) Ui.typingRequested(); }
        // a field is one line: Down / Up go on to the next / previous control, as in a list
        Keys.onDownPressed: { const n = input.nextItemInFocusChain(true); if (n) n.forceActiveFocus(Qt.TabFocusReason); }
        Keys.onUpPressed: { const n = input.nextItemInFocusChain(false); if (n) n.forceActiveFocus(Qt.BacktabFocusReason); }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: root.placeholder
            color: Theme.faint
            font: input.font
        }
    }
}
