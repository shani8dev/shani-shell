// A quick-settings tile: icon, title, state line. Click toggles; tiles with a
// detail view grow a chevron that opens it below the grid.
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string icon
    property string title
    property string subtitle: ""
    property bool on: false
    property bool hasDetail: false
    property bool expanded: false
    signal toggled()
    signal detail()

    implicitHeight: 58
    radius: 14
    color: on ? Theme.accent : (area.containsMouse ? Theme.pressed : Theme.hover)
    border.width: expanded ? 1 : 0
    border.color: Theme.accentLine
    Behavior on color { ColorAnimation { duration: Theme.anim } }

    readonly property color ink: on ? Theme.accentInk : Theme.text

    Icon {
        id: ic
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: 20
        color: root.ink
    }
    Column {
        anchors.left: ic.right
        anchors.leftMargin: 10
        anchors.right: chevron.visible ? chevron.left : parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
            width: parent.width
            text: root.title
            color: root.ink
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.subtitle
            color: root.on ? Theme.alpha(Theme.accentInk, 0.75) : Theme.dim
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 10
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => (e.button === Qt.RightButton && root.hasDetail) ? root.detail() : root.toggled()
    }

    Rectangle {
        id: chevron
        visible: root.hasDetail
        width: 26
        height: parent.height - 12
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        radius: 9
        color: chevArea.containsMouse ? Theme.alpha(root.ink, 0.15) : "transparent"
        Text {
            anchors.centerIn: parent
            text: root.expanded ? "▾" : "›"
            color: root.ink
            font.pixelSize: 15
        }
        MouseArea {
            id: chevArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.detail()
        }
    }
}
