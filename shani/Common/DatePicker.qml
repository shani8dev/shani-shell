// A date picker: click a day on a mini calendar.
// Value is "yyyy-MM-dd" — the same string timedatectl understands.
import QtQuick
import QtQuick.Layouts
import qs.Common
import "Month.js" as Month

ColumnLayout {
    id: root
    property string value: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property string label: ""
    signal picked(string date)

    Layout.fillWidth: true
    spacing: Theme.px(6)

    property date current: new Date()
    readonly property date month: new Date(current.getFullYear(), current.getMonth(), 1)
    readonly property bool sundayFirst: Settings.data.weekStartsOn === "sunday"
    readonly property int lead: Month.lead(month, sundayFirst)
    readonly property int days: Month.daysIn(month)
    readonly property var weekNames: Month.weekNames(sundayFirst, Tr.dayNamesShort)

    Text {
        visible: label !== ""
        text: label
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.type("caption")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(8)
        IconButton { icon: "go-previous"; tip: Tr.t("Previous month"); size: Theme.px(26); onClicked: current = new Date(current.getFullYear(), current.getMonth() - 1, 1) }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDate(root.month, "MMMM yyyy")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.current = new Date() }
            KeyFocus { onActivated: root.current = new Date() }
        }
        IconButton { icon: "go-next"; tip: Tr.t("Next month"); size: Theme.px(26); onClicked: current = new Date(current.getFullYear(), current.getMonth() + 1, 1) }
    }

    // years by click: a birth date is decades back (-10, -1, the year, +1, +10)
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.px(4)
        Button { text: "−10"; flat: true; Accessible.name: Tr.t("Ten years back"); onClicked: current = new Date(current.getFullYear() - 10, current.getMonth(), 1) }
        Button { text: "−1"; flat: true; Accessible.name: Tr.t("A year back"); onClicked: current = new Date(current.getFullYear() - 1, current.getMonth(), 1) }
        Text {
            text: String(root.current.getFullYear())
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.type("body")
            font.weight: Font.DemiBold
            Accessible.role: Accessible.StaticText
            Accessible.name: Tr.t("Year %1", text)
        }
        Button { text: "+1"; flat: true; Accessible.name: Tr.t("A year on"); onClicked: current = new Date(current.getFullYear() + 1, current.getMonth(), 1) }
        Button { text: "+10"; flat: true; Accessible.name: Tr.t("Ten years on"); onClicked: current = new Date(current.getFullYear() + 10, current.getMonth(), 1) }
    }

    // reach a distant month/year directly, without clicking through dozens of months
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        TextField {
            id: jumpMonth
            Layout.fillWidth: true
            placeholder: Tr.t("Jump to month — YYYY-MM")
            onAccepted: {
                const m = /^(\d{4})-(\d\d)$/.exec(jumpMonth.text.trim());
                if (m && +m[1] >= 100 && +m[2] >= 1 && +m[2] <= 12) {
                    root.current = new Date(+m[1], +m[2] - 1, 1);
                    jumpMonth.text = "";
                }
            }
        }
        Button {
            text: Tr.t("Go")
            onClicked: jumpMonth.accepted()
        }
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
                font.pixelSize: Theme.type("caption")
            }
        }

        Repeater {
            model: root.lead + root.days
            DayCell {
                required property int index
                readonly property int day: index - root.lead + 1
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(30)
                label: day > 0 ? String(day) : ""
                date: day > 0 ? new Date(root.month.getFullYear(), root.month.getMonth(), day) : null
                isSelected: day > 0 && root.format(day) === root.value
                isToday: day === new Date().getDate() && root.current.getMonth() === new Date().getMonth() && root.current.getFullYear() === new Date().getFullYear()
                onActivated: { const d = root.format(day); root.value = d; root.picked(d); }
            }
        }
    }

    function format(day) {
        const d = new Date(current.getFullYear(), current.getMonth(), day);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Text { text: root.value; color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.type("body"); font.weight: Font.DemiBold }
        Text { text: Tr.t("· tap a day to change"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption") }
    }

    // Quick picks
    // a label above the chips, not among them: a child as wide as its Flow makes the Flow re-lay out itself forever
    Text { Layout.fillWidth: true; text: Tr.t("Quick picks:"); color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption") }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
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
            onClicked: customDate.forceActiveFocus()
        }
    }

    // Custom date: type your own
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        TextField {
            id: customDate
            Layout.fillWidth: true
            placeholder: Tr.t("Custom date — YYYY-MM-DD, e.g. 2026-11-04")
            onAccepted: {
                const d = customDate.text.trim();
                const m = /^(\d{4})-(\d\d)-(\d\d)$/.exec(d);
                if (!m)
                    return;
                // the regex alone accepts 2026-02-31; only a real day can be set
                const parsed = new Date(+m[1], +m[2] - 1, +m[3]);
                if (parsed.getFullYear() !== +m[1] || parsed.getMonth() !== +m[2] - 1 || parsed.getDate() !== +m[3])
                    return;
                root.value = d;
                root.picked(d);
                root.current = parsed;
                customDate.text = "";
            }
        }
        Button {
            text: Tr.t("Use")
            onClicked: customDate.accepted()
        }
    }
}
