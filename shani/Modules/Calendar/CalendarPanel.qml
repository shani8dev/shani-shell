// The calendar surface (CalendarPanel): the month grid from
// Modules/ControlCenter/Calendar.qml, promoted to a full panel — arrows
// page through months, a day can be selected, and below the grid are the
// events Agenda (Services/Agenda.qml, Agenda.events) reports for that day.
// Read-only: refresh re-reads the calendars, "Open calendar" opens GNOME
// Calendar (the same calendars Agenda reads).
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.calendar && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-calendar"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) Agenda.refresh()

    MouseArea { anchors.fill: parent; onClicked: Ui.calendar = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: Ui.calendar = false }

    property date today: new Date()
    property int offset: 0
    property date selectedDate: new Date()
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

    function isSameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function hasEvents(day) {
        return Agenda.events.some(e => {
            const s = new Date(e.start * 1000);
            return s.getFullYear() === month.getFullYear() && s.getMonth() === month.getMonth() && s.getDate() === day;
        });
    }
    readonly property var selectedEvents: Agenda.events.filter(e => isSameDay(new Date(e.start * 1000), selectedDate))
    readonly property var monthEvents: Agenda.events.filter(e => {
        const s = new Date(e.start * 1000);
        return s.getFullYear() === month.getFullYear() && s.getMonth() === month.getMonth();
    })

    function stepMonth(delta) {
        offset += delta;
        const nm = new Date(today.getFullYear(), today.getMonth() + offset, 1);
        const maxDay = new Date(nm.getFullYear(), nm.getMonth() + 1, 0).getDate();
        selectedDate = new Date(nm.getFullYear(), nm.getMonth(), Math.min(selectedDate.getDate(), maxDay));
    }
    function goToday() {
        offset = 0;
        selectedDate = new Date();
    }
    function selectDay(day) {
        selectedDate = new Date(month.getFullYear(), month.getMonth(), day);
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: 440
        implicitHeight: Math.min(parent.height - 80, col.implicitHeight + 40)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Calendar")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "view-refresh"; size: 28; tip: Tr.t("Refresh"); onClicked: Agenda.refresh() }
                IconButton { icon: "window-close"; size: 28; onClicked: Ui.calendar = false }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconButton { icon: "go-previous"; size: 28; tip: Tr.t("Previous month"); onClicked: win.stepMonth(-1) }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(win.month, "MMMM yyyy")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.fontScale
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Button
                    Accessible.name: Tr.t("Back to today")
                    MouseArea { anchors.fill: parent; onClicked: win.goToday() }
                    KeyFocus { onActivated: win.goToday() }
                }
                IconButton { icon: "go-next"; size: 28; tip: Tr.t("Next month"); onClicked: win.stepMonth(1) }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: win.weekNumbers ? 8 : 7
                rowSpacing: 2
                columnSpacing: 2
                Text {
                    visible: win.weekNumbers
                    text: Tr.t("Wk")
                    color: Theme.faint
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                }
                Repeater {
                    model: win.weekNames
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
                    model: win.cells
                    Rectangle {
                        required property var modelData
                        readonly property bool isWeek: modelData.week !== undefined
                        readonly property int day: isWeek ? 0 : modelData.day
                        readonly property bool isToday: day === win.today.getDate() && win.offset === 0 && win.month.getMonth() === win.today.getMonth() && win.month.getFullYear() === win.today.getFullYear()
                        readonly property bool isSelected: !isWeek && day === win.selectedDate.getDate() && win.selectedDate.getMonth() === win.month.getMonth() && win.selectedDate.getFullYear() === win.month.getFullYear()
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 8
                        color: isSelected ? Theme.accent : isToday ? Theme.accentSoft : "transparent"
                        Accessible.role: isWeek ? Accessible.StaticText : Accessible.Button
                        Accessible.name: isWeek ? Tr.t("Week %1").arg(modelData.week) : Qt.formatDate(new Date(win.month.getFullYear(), win.month.getMonth(), day), "dddd d MMMM yyyy")
                        Text {
                            anchors.centerIn: parent
                            visible: parent.day > 0 || parent.isWeek
                            text: parent.isWeek ? parent.modelData.week : parent.day
                            color: parent.isSelected ? Theme.accentInk : parent.isWeek ? Theme.faint : parent.isToday ? Theme.accent : Theme.text
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                            font.weight: parent.isSelected || parent.isToday ? Font.DemiBold : Font.Normal
                        }
                        Rectangle {
                            visible: !parent.isWeek && win.hasEvents(parent.day)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 5
                            height: 5
                            radius: 2.5
                            color: parent.isSelected ? Theme.accentInk : Theme.accent
                        }
                        MouseArea {
                            visible: !parent.isWeek
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.selectDay(parent.day)
                        }
                        KeyFocus {
                            visible: !parent.isWeek
                            onActivated: win.selectDay(parent.day)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.stroke
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Qt.formatDate(win.selectedDate, "dddd d MMMM yyyy")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: win.monthEvents.length > 0
                    text: Tr.t("%1 in this month").arg(win.monthEvents.length)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(190, dayList.implicitHeight + 4)
                Layout.minimumHeight: 24
                contentHeight: dayList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: dayList
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: win.selectedEvents
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "x-office-calendar"
                            title: modelData.summary
                            subtitle: Agenda.when(modelData) + (modelData.location ? " · " + modelData.location : "") + (modelData.calendar ? " · " + modelData.calendar : "")
                            onClicked: { Ui.calendar = false; Agenda.openCalendar(); }
                        }
                    }
                    EmptyState {
                        visible: win.selectedEvents.length === 0
                        icon: "x-office-calendar"
                        title: Tr.t("Nothing that day")
                        subtitle: Agenda.available ? Tr.t("No events for this day") : Tr.t("Add a calendar in Settings > Your account")
                        actionText: Agenda.available ? Tr.t("Refresh") : ""
                        onAction: Agenda.refresh()
                    }
                }
            }

            Button {
                Layout.fillWidth: true
                text: Tr.t("Open calendar")
                kind: "primary"
                onClicked: { Ui.calendar = false; Agenda.openCalendar(); }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Esc closes · title returns to today")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: Ui.calendar = false }
    Shortcut { sequence: "Ctrl+R"; onActivated: Agenda.refresh() }
}
