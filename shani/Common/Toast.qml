// A temporary toast: message + optional undo button, auto-dismiss after 5 s.
import QtQuick
import QtQuick.Layouts
import qs.Common

Rectangle {
    id: root
    property string message: ""
    property bool showUndo: false
    property var undoValue: null     // the previous value to restore
    signal undo()

    visible: root.message !== ""
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim * 2; easing.type: Easing.InOutQuad } }

    onVisibleChanged: if (visible) opacity = 1; else opacity = 0
    Component.onCompleted: if (visible) opacity = 1

    anchors.bottom: parent ? parent.bottom : undefined
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    anchors.margins: 20
    width: Math.min(parent ? parent.width - 40 : 600, 640)
    implicitHeight: 44
    radius: Theme.radiusLarge
    color: Theme.glassStrong
    border.width: 1
    border.color: Theme.stroke

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: root.message
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 12 * Theme.fontScale
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
        }
        Button {
            visible: root.showUndo
            text: Tr.t("Undo")
            kind: "primary"
            implicitHeight: 28
            onClicked: root.undo()
        }
    }
    Timer {
        running: root.visible
        interval: 5000
        onTriggered: root.message = ""
    }
}
