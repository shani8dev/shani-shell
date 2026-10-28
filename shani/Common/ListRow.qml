// One row in a detail list (a network, a device, an output).
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string icon
    property string title
    property string subtitle: ""
    property bool selected: false
    property string trailing: ""
    default property alias extra: tail.data
    signal clicked()

    Accessible.role: Accessible.ListItem
    Accessible.name: root.title
    Accessible.description: root.subtitle
    Accessible.selected: root.selected
    Accessible.onPressAction: root.clicked()

    implicitHeight: 40
    radius: 10
    color: selected ? Theme.accentSoft : (area.containsMouse ? Theme.hover : "transparent")

    Icon {
        id: ic
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: 16
        color: root.selected ? Theme.accent : Theme.text
    }
    Column {
        anchors.left: ic.right
        anchors.leftMargin: 10
        anchors.right: tail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            text: root.title
            color: root.selected ? Theme.accent : Theme.text
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
        }
        Text {
            width: parent.width
            visible: root.subtitle !== ""
            text: root.subtitle
            color: Theme.dim
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 10 * Theme.fontScale
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    Row {
        id: tail
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text {
            visible: root.trailing !== ""
            text: root.trailing
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * Theme.fontScale
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
