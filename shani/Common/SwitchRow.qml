// A labelled on/off switch.
import QtQuick
import QtQuick.Layouts
import qs.Common

RowLayout {
    id: root
    property string text
    property string hint: ""
    property bool checked: false
    signal toggled(bool on)
    spacing: 10

    Column {
        Layout.fillWidth: true
        Text { text: root.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
        Text { visible: root.hint !== ""; text: root.hint; color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 }
    }
    Rectangle {
        implicitWidth: 40
        implicitHeight: 22
        radius: 11
        color: root.checked ? Theme.accent : Theme.pressed
        Behavior on color { ColorAnimation { duration: Theme.anim } }
        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Theme.accentInk : Theme.text
            Behavior on x { NumberAnimation { duration: Theme.anim } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled(!root.checked)
        }
    }
}
