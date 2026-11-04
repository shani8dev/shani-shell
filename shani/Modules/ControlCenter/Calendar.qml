// A month at a glance; arrows page through months, the title returns to today.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property date today: new Date()
    property int offset: 0
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property bool sundayFirst: Settings.data.weekStartsOn === "sunday"
    // blanks before the 1st, then the days; Monday-first or Sunday-first
    readonly property int lead: sundayFirst ? month.getDay() : (month.getDay() + 6) % 7
    readonly property int days: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
    readonly property bool weekNumbers: Settings.data.weekNumbers
    // ISO 8601: the week holding the year's first Thursday is week 1
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 3 - (t.getUTCDay() + 6) % 7);
        const y = new Date(Date.UTC(t.getUTCFullYear(), 0, 4));
        return 1 + Math.round(((t - y) / 86400000 - 3 + (y.getUTCDay() + 6) % 7) / 7);
    }
    // the grid, cell by cell: an optional week number, then seven days, per row
    readonly property var cells: {
        const out = [];
        const rows = Math.ceil((lead + days) / 7);
        for (let r = 0; r < rows; r++) {
            if (weekNumbers) {
                // the row's Thursday-anchored week: any day of the row inside the month will do
                const first = Math.max(1, r * 7 - lead + 1);
                out.push({ week: isoWeek(new Date(month.getFullYear(), month.getMonth(), first)) });
            }
            for (let c = 0; c < 7; c++) {
                const day = r * 7 + c - lead + 1;
                if (day > days)
                    break;
                out.push({ day: day });
            }
        }
        return out;
    }
    readonly property var weekNames: sundayFirst ? ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
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
        columns: root.weekNumbers ? 8 : 7
        rowSpacing: 2
        columnSpacing: 2
        Text {
            visible: root.weekNumbers
            text: Tr.t("Wk")
            color: Theme.faint
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font
            font.pixelSize: 10 * Theme.fontScale
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
                font.pixelSize: 10 * Theme.fontScale
            }
        }
        Repeater {
            model: root.cells
            Rectangle {
                required property var modelData
                readonly property bool isWeek: modelData.week !== undefined
                readonly property int day: isWeek ? 0 : modelData.day
                readonly property bool isToday: day === root.today.getDate() && root.offset === 0
                Layout.fillWidth: true
                implicitHeight: 28
                radius: 8
                color: isToday ? Theme.accent : "transparent"
                Text {
                    anchors.centerIn: parent
                    visible: parent.day > 0 || parent.isWeek
                    text: parent.isWeek ? parent.modelData.week : parent.day
                    color: parent.isToday ? Theme.accentInk : parent.isWeek ? Theme.faint : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                    font.weight: parent.isToday ? Font.DemiBold : Font.Normal
                }
            }
        }
    }
}
