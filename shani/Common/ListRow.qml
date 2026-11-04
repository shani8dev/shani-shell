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
    // flashed after a search lands here (see Ui.flashSetting)
    readonly property bool highlighted: Ui.settingsFlash.length > 0 && String(root.title).toLowerCase().indexOf(Ui.settingsFlash) >= 0

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
        focus: true
        onClicked: root.clicked()
    }
    Rectangle {
        id: focusRing
        anchors.fill: parent
        anchors.margins: -2
        radius: parent.radius + 2
        color: "transparent"
        border.color: Theme.accent
        border.width: 2
        visible: root.activeFocus
        z: 10
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

    // a search landed here: a pulsing accent edge until the flash clears
    Rectangle {
        id: flashRing
        anchors.fill: parent
        anchors.margins: -3
        radius: root.radius + 3
        color: Theme.alpha(Theme.accent, 0.18)
        border.width: 1.5
        border.color: Theme.alpha(Theme.accent, 0.8)
        visible: root.highlighted
        z: 10
        SequentialAnimation on opacity {
            running: root.highlighted
            loops: Animation.Infinite
            NumberAnimation { from: 0.35; to: 1; duration: 420; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.35; duration: 420; easing.type: Easing.InOutSine }
        }
    }
}
