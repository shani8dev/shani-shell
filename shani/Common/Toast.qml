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

    // Stay visible through the exit animation; hiding on message-clear would
    // cut the fade short because Qt Quick does not render invisible items.
    property bool _live: false
    visible: _live
    opacity: 0
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.anim * 2
            easing.type: Easing.InOutQuad
            onFinished: if (root.opacity === 0) root._live = false
        }
    }

    onMessageChanged: {
        if (message !== "") {
            _live = true; opacity = 1; dismiss.restart();
            Qt.accessibleAnnounce(message, Qt.LowPriority);
        } else opacity = 0;
    }
    Component.onCompleted: if (message !== "") { _live = true; opacity = 1; dismiss.restart(); }

    anchors.bottom: parent ? parent.bottom : undefined
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    anchors.margins: Theme.px(20)
    width: Math.min(parent ? parent.width - 40 : 600, 640)
    implicitHeight: Theme.px(44)
    radius: Theme.radiusLarge
    color: Theme.glassStrong
    border.width: 1
    border.color: Theme.stroke

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(10)
        spacing: Theme.px(8)
        Text {
            Layout.fillWidth: true
            text: root.message
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
        }
        Button {
            visible: root.showUndo
            text: Tr.t("Undo")
            kind: "primary"
            implicitHeight: Theme.px(28)
            onClicked: root.undo()
        }
    }
    Timer {
        id: dismiss
        interval: 5000
        onTriggered: root.message = ""
    }
}
