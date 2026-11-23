// One row in a detail list (a network, a device, an output).
import QtQuick
import qs.Common

Rectangle {
    id: root
    property string icon
    property string title
    property string subtitle: ""
    property bool selected: false
    property bool interactive: true      // a row that only shows a value, not one that opens something
    property string trailing: ""
    default property alias extra: tail.data
    signal clicked()
    // flashed after a search lands here (see Ui.flashSetting)
    readonly property bool highlighted: Ui.settingsFlash.length > 0 && String(root.title).toLowerCase().indexOf(Ui.settingsFlash) >= 0

    Accessible.role: interactive ? Accessible.ListItem : Accessible.StaticText
    Accessible.name: root.title
    Accessible.description: root.subtitle
    Accessible.selected: root.selected
    Accessible.onPressAction: if (root.interactive) root.clicked()

    implicitHeight: Math.max(Theme.px(40), Theme.touchTarget)
    radius: Theme.radiusSmall
    color: selected ? Theme.accentSoft : (interactive && area.containsMouse ? Theme.hover : "transparent")

    Icon {
        id: ic
        anchors.left: parent.left
        anchors.leftMargin: Theme.px(10)
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: Theme.px(16)
        color: root.selected ? Theme.accent : Theme.text
    }
    Column {
        anchors.left: ic.right
        anchors.leftMargin: Theme.px(10)
        anchors.right: tail.left
        anchors.rightMargin: Theme.px(8)
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            text: root.title
            color: root.selected ? Theme.accent : Theme.text
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
        Text {
            width: parent.width
            visible: root.subtitle !== ""
            text: root.subtitle
            color: Theme.dim
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
    KeyFocus { enabled: root.interactive; onActivated: root.clicked() }
    Row {
        id: tail
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(6)
        Icon {
            visible: root.selected
            name: "object-select-symbolic"
            size: Theme.px(14)
            color: Theme.accent
            anchors.verticalCenter: parent ? parent.verticalCenter : 0
        }
        Text {
            visible: root.trailing !== ""
            text: root.trailing
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
            anchors.verticalCenter: parent ? parent.verticalCenter : 0
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
            running: root.highlighted && !Settings.data.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: 0.35; to: 1; duration: Theme.mot(420); easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.35; duration: Theme.mot(420); easing.type: Easing.InOutSine }
        }
    }
}
