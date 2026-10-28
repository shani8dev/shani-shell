// A round icon button: hover and press states, optional "on" fill.
import QtQuick

Rectangle {
    id: root
    property string icon
    property bool on: false
    property real size: 32
    property color iconColor: on ? Theme.accentInk : Theme.text
    property string tip: ""
    signal clicked()
    signal rightClicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: on ? Theme.accent : (area.pressed ? Theme.pressed : (area.containsMouse ? Theme.hover : "transparent"))
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.size * 0.55
        color: root.iconColor
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
}
