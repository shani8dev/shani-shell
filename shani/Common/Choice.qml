// One of a row of mutually exclusive chips.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string text
    property bool selected: false
    signal clicked()
    implicitWidth: label.implicitWidth + 20
    implicitHeight: 28
    radius: 9
    color: selected ? Theme.accent : (area.containsMouse ? Theme.pressed : Theme.hover)
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.selected ? Theme.accentInk : Theme.text
        font.family: Theme.font
        font.pixelSize: 11
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
