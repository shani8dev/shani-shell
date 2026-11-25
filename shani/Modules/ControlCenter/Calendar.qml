// A month at a glance; arrows page through months, the title returns to today.
import QtQuick
import QtQuick.Layouts
import qs.Common
import "../../Common/Month.js" as Month

ColumnLayout {
    id: root
    property date today: new Date()
    property int offset: 0
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property bool sundayFirst: Settings.data.weekStartsOn === "sunday"
    readonly property bool weekNumbers: Settings.data.weekNumbers
    // blanks, days and ISO week numbers: Common/Month.js, shared with every calendar
    readonly property var cells: Month.cells(month, sundayFirst, weekNumbers)
    readonly property var weekNames: Month.weekNames(sundayFirst, Tr.dayNamesShort)
    spacing: Theme.px(6)

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(root.month, "MMMM yyyy")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(13) * Theme.fontScale
            font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; onClicked: root.offset = 0 }
            KeyFocus { onActivated: root.offset = 0 }
        }
        IconButton { icon: "go-previous"; tip: Tr.t("Previous"); size: Theme.px(26); onClicked: root.offset-- }
        IconButton { icon: "go-next"; tip: Tr.t("Next"); size: Theme.px(26); onClicked: root.offset++ }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: root.weekNumbers ? 8 : 7
        rowSpacing: 2
        columnSpacing: 2
        Text {
            visible: root.weekNumbers
            text: Tr.t("Wk")
            color: Theme.faint
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
        }
        Repeater {
            model: root.weekNames
            Text {
                required property string modelData
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(10) * Theme.fontScale
            }
        }
        Repeater {
            model: root.cells
            DayCell {
                required property var modelData
                readonly property int day: isWeek ? 0 : modelData.day
                Layout.fillWidth: true
                implicitHeight: Theme.px(28)
                isWeek: modelData.week !== undefined
                label: isWeek ? String(modelData.week) : (day > 0 ? String(day) : "")
                date: day > 0 ? new Date(root.month.getFullYear(), root.month.getMonth(), day) : null
                isToday: day === root.today.getDate() && root.offset === 0
                interactive: false               // a glance: the Calendar app is where days are picked
            }
        }
    }
}
