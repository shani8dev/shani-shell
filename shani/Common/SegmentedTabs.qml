// Pill segmented control with one sliding thumb — ported from Ananta UI
// (ananta-os/apps/ui/SegmentedTabs.qml). options is a list of labels; activated() reports the
// chosen index. Reaches each segment by keyboard and controller through KeyFocus.
import QtQuick
import qs.Common

Rectangle {
    id: tabs
    property var options: []
    property int currentIndex: 0
    property int segmentWidth: Theme.px(100)
    signal activated(int index)

    implicitWidth: options.length * segmentWidth + Theme.px(8)
    implicitHeight: Theme.px(40)
    radius: Theme.radius
    color: Theme.surface2
    border.width: 1
    border.color: Theme.stroke

    Rectangle {
        id: thumb
        x: Theme.px(4) + tabs.currentIndex * tabs.segmentWidth
        y: Theme.px(4)
        width: tabs.segmentWidth
        height: tabs.height - Theme.px(8)
        radius: Math.max(4, Theme.radiusSmall - 2)
        color: Theme.card
        border.width: 1
        border.color: Theme.stroke
        Behavior on x { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    }

    Row {
        x: Theme.px(4)
        y: Theme.px(4)
        Repeater {
            model: tabs.options
            delegate: Item {
                id: segment
                required property var modelData
                required property int index
                width: tabs.segmentWidth
                height: tabs.height - Theme.px(8)

                Text {
                    anchors.centerIn: parent
                    text: segment.modelData
                    color: segment.index === tabs.currentIndex ? Theme.text : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        tabs.currentIndex = segment.index
                        tabs.activated(segment.index)
                    }
                }
                KeyFocus {
                    enabled: tabs.enabled
                    onActivated: {
                        tabs.currentIndex = segment.index
                        tabs.activated(segment.index)
                    }
                }

                Accessible.role: Accessible.PageTab
                Accessible.name: segment.modelData
                Accessible.selected: segment.index === tabs.currentIndex
                Accessible.onPressAction: tabs.activated(segment.index)
            }
        }
    }
}
