// A date picker: click a day on a mini calendar.
// Value is "yyyy-MM-dd" — the same string timedatectl understands.
import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    id: root
    property string value: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property string label: ""
    signal picked(string date)

    Layout.fillWidth: true
    spacing: 6

    property date current: new Date()
    readonly property date month: new Date(current.getFullYear(), current.getMonth(), 1)
    readonly property bool sundayFirst: Settings.data.weekStartsOn === "sunday"
    readonly property int lead: sundayFirst ? month.getDay() : (month.getDay() + 6) % 7
    readonly property int days: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
    readonly property var weekNames: sundayFirst ? ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    Text {
        visible: label !== ""
        text: label
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSmall * Theme.fontScale
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        IconButton { icon: "go-previous"; size: 26; onClicked: current = new Date(current.getFullYear(), current.getMonth() - 1, 1) }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDate(root.month, "MMMM yyyy")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13 * Theme.fontScale
            font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.current = new Date() }
            KeyFocus { onActivated: root.current = new Date() }
        }
        IconButton { icon: "go-next"; size: 26; onClicked: current = new Date(current.getFullYear(), current.getMonth() + 1, 1) }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 2
        columnSpacing: 2

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
            model: root.lead + root.days
            Rectangle {
                required property int index
                readonly property int day: index - root.lead + 1
                readonly property bool isSelected: day > 0 && root.format(day) === root.value
                readonly property bool isToday: day === new Date().getDate() && current.getMonth() === new Date().getMonth() && current.getFullYear() === new Date().getFullYear()
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: Theme.radiusToken("xs")
                color: isSelected ? Theme.accent : (isToday ? Theme.hover : "transparent")
                border.width: isToday && !isSelected ? 1 : 0
                border.color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    visible: parent.day > 0
                    text: parent.day
                    color: parent.isSelected ? Theme.accentInk : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                    font.weight: parent.isSelected || parent.isToday ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: parent.day > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const d = root.format(parent.day);
                        root.value = d;
                        root.picked(d);
                    }
                }
                KeyFocus { onActivated: { const d = root.format(parent.day); root.value = d; root.picked(d); } }
            }
        }
    }

    function format(day) {
        const d = new Date(current.getFullYear(), current.getMonth(), day);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text { text: root.value; color: Theme.accent; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; font.weight: Font.DemiBold }
        Text { text: Tr.t("· tap a day to change"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
    }

    // Quick picks
    // a label above the chips, not among them: a child as wide as its Flow makes the Flow re-lay out itself forever
    Text { Layout.fillWidth: true; text: Tr.t("Quick picks:"); color: Theme.faint; font.family: Theme.font; font.pixelSize: 10 * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Choice {
            text: Tr.t("Today")
            selected: root.value === Qt.formatDate(new Date(), "yyyy-MM-dd")
            onClicked: {
                const d = Qt.formatDate(new Date(), "yyyy-MM-dd");
                root.value = d;
                root.picked(d);
                root.current = new Date();
            }
        }
        Choice {
            text: Tr.t("Tomorrow")
            selected: root.value === Qt.formatDate(new Date(Date.now() + 86400000), "yyyy-MM-dd")
            onClicked: {
                const d = new Date(Date.now() + 86400000);
                root.value = Qt.formatDate(d, "yyyy-MM-dd");
                root.picked(root.value);
                root.current = d;
            }
        }
        Choice {
            text: Tr.t("Other…")
            selected: root.value !== Qt.formatDate(new Date(), "yyyy-MM-dd") && root.value !== Qt.formatDate(new Date(Date.now() + 86400000), "yyyy-MM-dd")
            onClicked: { }
        }
    }

    // Custom date: type your own
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            id: customDate
            Layout.fillWidth: true
            placeholder: Tr.t("Custom date — YYYY-MM-DD, e.g. 2026-11-04")
            onAccepted: {
                const d = customDate.text.trim();
                if (/^\d{4}-\d\d-\d\d$/.test(d)) {
                    root.value = d;
                    root.picked(d);
                    customDate.text = "";
                }
            }
        }
        Button {
            text: Tr.t("Use")
            onClicked: customDate.accepted()
        }
    }
}
