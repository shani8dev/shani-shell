// A text button: plain, accent (primary) or danger.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string text
    property string kind: "plain"      // plain | primary | danger
    signal clicked()

    Accessible.role: Accessible.Button
    Accessible.name: root.text
    Accessible.onPressAction: root.clicked()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 32
    radius: 10
    color: kind === "primary" ? Theme.accent : kind === "danger" ? Theme.alpha(Theme.danger, area.containsMouse ? 0.35 : 0.22)
         : (area.containsMouse ? Theme.pressed : Theme.hover)
    opacity: enabled ? 1 : 0.5
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.kind === "primary" ? Theme.accentInk : root.kind === "danger" ? Theme.danger : Theme.text
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
        font.weight: Font.DemiBold
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
