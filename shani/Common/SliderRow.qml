// Icon button + slider (+ optional chevron). The slider is our own: drag,
// click-to-set and wheel, so it needs no Qt Quick Controls style.
import QtQuick
import QtQuick.Layouts
import qs.Common
import "WheelInput.js" as WheelInput

RowLayout {
    id: root
    property string icon
    property real value: 0
    property bool muted: false
    property bool hasDetail: false
    property bool expanded: false
    property real level: -1              // a live input level (0..1) behind the track; -1: none
    signal moved(real v)
    signal iconClicked()
    signal detail()

    spacing: 8

    IconButton {
        icon: root.icon
        size: 34
        iconColor: root.muted ? Theme.dim : Theme.text
        onClicked: root.iconClicked()
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: 28

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 8
            radius: 4
            color: Theme.hover
            // what the microphone hears right now, under the set level
            Rectangle {
                visible: root.level >= 0
                width: parent.width * Math.max(0, Math.min(1, root.level))
                height: parent.height
                radius: 4
                color: Theme.alpha(Theme.accent, 0.35)
                Behavior on width { NumberAnimation { duration: 60 } }
            }
            Rectangle {
                width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.value)))
                height: parent.height
                radius: 4
                color: root.muted ? Theme.faint : Theme.accent
            }
        }
        Rectangle {
            x: Math.max(0, Math.min(parent.width - width, parent.width * root.value - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: Theme.text
            border.width: 3
            border.color: root.muted ? Theme.faint : Theme.accent
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function at(x) {
                root.moved(Math.max(0, Math.min(1, x / width)));
            }
            onPressed: m => at(m.x)
            onPositionChanged: m => pressed && at(m.x)
            // a wheel notch is one step; a finger slides it by its own pixels
            onWheel: w => {
                const delta = WheelInput.stepDelta(w, 0.05, 40);
                if (delta === 0)
                    return;
                root.moved(Math.max(0, Math.min(1, root.value + delta)));
            }
        }
        // keyboard and controller: Left / Right move it by 5 %
        KeyFocus {
            // what it sets, said plainly: the icon names it
            name: root.Accessible.name || (/volume|audio|speaker/.test(root.icon) ? Tr.t("Volume") : /mic/.test(root.icon) ? Tr.t("Microphone")
                : /bright|display/.test(root.icon) ? Tr.t("Brightness") : root.icon)
            slider: true
            onStep: dir => root.moved(Math.max(0, Math.min(1, root.value + dir * 0.05)))
            onActivated: root.iconClicked()
        }
    }

    Text {
        Layout.preferredWidth: 34
        text: Math.round(root.value * 100) + "%"
        color: Theme.dim
        horizontalAlignment: Text.AlignRight
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }

    IconButton {
        visible: root.hasDetail
        icon: "go-next"
        size: 28
        rotation: root.expanded ? 90 : 0
        onClicked: root.detail()
    }
}
