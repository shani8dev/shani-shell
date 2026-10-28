// A month at a glance; arrows page through months, the title returns to today.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property date today: new Date()
    property int offset: 0
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    // Monday-first grid: blanks before the 1st, then the days
    readonly property int lead: (month.getDay() + 6) % 7
    readonly property int days: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(root.month, "MMMM yyyy")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13 * Theme.fontScale
            font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; onClicked: root.offset = 0 }
        }
        IconButton { icon: "go-previous"; size: 26; onClicked: root.offset-- }
        IconButton { icon: "go-next"; size: 26; onClicked: root.offset++ }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 2
        columnSpacing: 2
        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            Text {
                required property string modelData
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
        Repeater {
            model: root.lead + root.days
            Rectangle {
                required property int index
                readonly property int day: index - root.lead + 1
                readonly property bool isToday: day === root.today.getDate() && root.offset === 0
                Layout.fillWidth: true
                implicitHeight: 28
                radius: 8
                color: isToday ? Theme.accent : "transparent"
                Text {
                    anchors.centerIn: parent
                    visible: parent.day > 0
                    text: parent.day
                    color: parent.isToday ? Theme.accentInk : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                    font.weight: parent.isToday ? Font.DemiBold : Font.Normal
                }
            }
        }
    }
}
