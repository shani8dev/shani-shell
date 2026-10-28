// A single-line input on a glass well; `secret` masks it.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property alias text: input.text
    property alias input: input
    property string placeholder
    property bool secret: false
    signal accepted()

    implicitHeight: 38
    radius: 10
    color: Theme.hover
    border.width: 1
    border.color: input.activeFocus ? Theme.accent : Theme.stroke

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.accent
        font.family: Theme.font
        font.pixelSize: 13
        echoMode: root.secret ? TextInput.Password : TextInput.Normal
        clip: true
        onAccepted: root.accepted()
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: root.placeholder
            color: Theme.faint
            font: input.font
        }
    }
}
