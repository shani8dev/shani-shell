// One big round action: Call, End and the in-call controls. The label is the
// accessible name; the circle is the touch target, not a decoration.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string text
    property color fill: Theme.accent
    property bool isOn: false
    signal clicked()

    width: Theme.px(84)
    height: Theme.px(84)
    radius: width / 2
    color: !root.enabled ? Theme.alpha(Theme.text, 0.12)
         : area.pressed ? Theme.alpha(root.fill, 0.72)
         : area.containsMouse ? Theme.alpha(root.fill, 0.86) : root.fill
    border.width: root.isOn ? 2 : 0
    border.color: Theme.text

    Accessible.role: Accessible.Button
    Accessible.name: root.text
    Accessible.onPressAction: if (root.enabled) root.clicked()

    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.enabled ? Theme.inkOn(root.fill) : Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.type("body")
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    KeyFocus { enabled: root.enabled && root.visible; onActivated: root.clicked() }
}
