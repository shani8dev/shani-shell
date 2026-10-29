// A bar item: icon and/or label on a pill that lights up on hover.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string icon
    property string label
    property string name: ""            // what a screen reader says, when label/icon would not do
    property color tint: Theme.text
    property bool active: false
    property bool mono: false
    property real maxLabelWidth: 10000
    default property alias extra: row.data
    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal scrolled(int dir)

    Accessible.role: Accessible.Button
    Accessible.name: root.name || (root.label !== "" ? root.label : root.icon.replace(/-/g, " "))
    Accessible.onPressAction: root.clicked()

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 28
    radius: 9
    color: active ? Theme.accentSoft : (area.containsMouse ? Theme.hover : "transparent")
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon {
            visible: root.icon !== ""
            name: root.icon
            size: 16
            color: root.tint
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.label !== ""
            width: Math.min(implicitWidth, root.maxLabelWidth)
            elide: Text.ElideRight
            text: root.label
            color: root.tint
            font.family: root.mono ? Theme.mono : Theme.font
            font.pixelSize: (root.mono ? Theme.fontSmall : 12) * Theme.fontScale
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked() : e.button === Qt.MiddleButton ? root.middleClicked() : root.clicked()
        onWheel: w => root.scrolled(w.angleDelta.y > 0 ? 1 : -1)
    }
}
