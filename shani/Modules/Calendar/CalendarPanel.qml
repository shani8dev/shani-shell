// The calendar surface (CalendarPanel): the month grid from
// Modules/ControlCenter/Calendar.qml, promoted to a full panel — arrows
// page through months, a day can be selected, and below the grid are the
// events Agenda (Services/Agenda.qml, Agenda.events) reports for that day.
// Events can be created, edited and deleted here (summary/title, start, end,
// all-day, location) — writes go over EDS via bridge/agenda.py, falling back
// to a Chronoa calendar_edit ask when EDS is unavailable (see Agenda.qml).
// A search box filters the day's events by title. This surface IS "the
// calendar": Agenda.openCalendar() points here, never at GNOME Calendar.
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

    onVisibleChanged: if (visible) { Agenda.refresh(); win.view = Ui.calendarView || "month"; }
    Connections { target: Ui; function onCalendarViewChanged() { win.view = Ui.calendarView || "month"; } }

    MouseArea { anchors.fill: parent; onClicked: Ui.calendar = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: { if (win.editor) win.closeEditor(); else Ui.calendar = false; } }

    property date today: new Date()
    property int offset: 0
    property date selectedDate: new Date()
    // month view or week view: synced to Ui.calendarView so the CLI/shell
    // and the surface agree
    property string view: Ui.calendarView || "month"
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property date weekAnchor: new Date(today.getFullYear(), today.getMonth(), today.getDate() + (offset * 7))
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
    // title search lives on Agenda (so IPC `calendarSearch` uses the same box)
    readonly property var dayEvents: Agenda.events.filter(e => isSameDay(new Date(e.start * 1000), selectedDate))
    readonly property var shownEvents: dayEvents.filter(e => Agenda.search === "" || String(e.summary || "").toLowerCase().indexOf(Agenda.search.toLowerCase()) >= 0)
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
    function stepView(delta) {
        if (view === "week")
            offset += delta;
        else
            offset += delta;
    }
    readonly property string weekLabel: {
        const a = new Date(weekAnchor.getFullYear(), weekAnchor.getMonth(), weekAnchor.getDate() - weekAnchor.getDay());
        const b = new Date(a.getFullYear(), a.getMonth(), a.getDate() + 6);
        return Qt.formatDate(a, "d MMM") + " – " + Qt.formatDate(b, "d MMM yyyy");
    }
    readonly property var weekEvents: {
        const a = new Date(weekAnchor.getFullYear(), weekAnchor.getMonth(), weekAnchor.getDate() - weekAnchor.getDay());
        const b = new Date(a.getFullYear(), a.getMonth(), a.getDate() + 7);
        return Agenda.events.filter(e => { const s = new Date(e.start * 1000); return s >= a && s < b; });
    }
    function weekEventsForHour(col, hour) {
        const a = new Date(weekAnchor.getFullYear(), weekAnchor.getMonth(), weekAnchor.getDate() - weekAnchor.getDay() + col);
        return weekEvents.filter(e => new Date(e.start * 1000).getHours() === hour);
    }

    // ---- event editor ------------------------------------------------------
    property bool editor: false
    property var editingEvent: null     // the event being edited, null = new
    property bool fAllDay: false
    property string formError: ""

    function _fmtDate(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }
    function _fmtTime(d) { return Qt.formatTime(d, "HH:mm"); }
    function openEditor(e) {
        editingEvent = e || null;
        formError = "";
        if (e) {
            const s = new Date(e.start * 1000), en = new Date(e.end * 1000);
            fTitle.text = e.summary || "";
            fLocation.text = e.location || "";
            fDateA.text = _fmtDate(s);
            fTimeA.text = _fmtTime(s);
            fDateB.text = _fmtDate(en);
            fTimeB.text = _fmtTime(en);
            fAllDay = !!e.allDay;
        } else {
            const s = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate(), 9, 0);
            const en = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate(), 10, 0);
            fTitle.text = "";
            fLocation.text = "";
            fDateA.text = _fmtDate(s);
            fTimeA.text = _fmtTime(s);
            fDateB.text = _fmtDate(en);
            fTimeB.text = _fmtTime(en);
            fAllDay = false;
        }
        editor = true;
    }
    function closeEditor() { editor = false; formError = ""; }
    // "yyyy-MM-dd" + "HH:mm" -> seconds, or NaN
    function _parseDateTime(dateText, timeText) {
        const d = String(dateText || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
        if (!d)
            return NaN;
        let h = 0, mi = 0;
        if (!fAllDay) {
            const t = String(timeText || "").match(/^(\d{2}):(\d{2})$/);
            if (!t)
                return NaN;
            h = Number(t[1]);
            mi = Number(t[2]);
            if (h > 23 || mi > 59)
                return NaN;
        }
        const dt = new Date(Number(d[1]), Number(d[2]) - 1, Number(d[3]), h, mi);
        if (dt.getFullYear() !== Number(d[1]) || dt.getMonth() !== Number(d[2]) - 1 || dt.getDate() !== Number(d[3]))
            return NaN;
        return Math.floor(dt.getTime() / 1000);
    }
    function saveEditor() {
        const title = fTitle.text.trim();
        if (title === "") {
            formError = Tr.t("An event needs a title");
            return;
        }
        const start = _parseDateTime(fDateA.text, fTimeA.text);
        const end = _parseDateTime(fDateB.text, fTimeB.text);
        if (isNaN(start) || isNaN(end) || end <= start) {
            formError = Tr.t("Check the dates and times (end after start)");
            return;
        }
        const payload = {
            summary: title,
            start: start,
            end: end,
            location: fLocation.text.trim(),
            allDay: fAllDay,
            calendar: editingEvent && editingEvent.calendar ? editingEvent.calendar : "",
            uid: editingEvent && editingEvent.uid ? editingEvent.uid : ""
        };
        if (editingEvent)
            Agenda.editEvent(payload);
        else
            Agenda.addEvent(payload);
        closeEditor();
        Agenda.refresh();
    }
    function deleteEditor() {
        if (!editingEvent)
            return;
        Agenda.deleteEvent({ summary: editingEvent.summary, start: editingEvent.start, end: editingEvent.end,
            location: editingEvent.location, allDay: editingEvent.allDay,
            calendar: editingEvent.calendar, uid: editingEvent.uid });
        closeEditor();
        Agenda.refresh();
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: win.view === "week" ? Math.min(760, parent.width - 80) : 440
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
                IconButton { icon: "view-refresh"; size: 28; tip: Tr.t("Refresh"); onClicked: { Agenda.refresh(); Agenda.refreshCalendars(); Agenda.refreshAccounts(); } }
                IconButton { icon: "window-close"; size: 28; onClicked: Ui.calendar = false }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Choice { text: Tr.t("Month"); selected: win.view === "month"; onClicked: { Ui.calendarView = "month"; Agenda.refresh(); } }
                Choice { text: Tr.t("Week"); selected: win.view === "week"; onClicked: { Ui.calendarView = "week"; Agenda.refresh(); } }
                Item { Layout.fillWidth: true }
                Choice { text: Tr.t("Today"); onClicked: win.goToday() }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconButton { icon: "go-previous"; size: 28; tip: win.view === "week" ? Tr.t("Previous week") : Tr.t("Previous month"); onClicked: win.stepView(-1) }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: win.view === "week" ? win.weekLabel : Qt.formatDate(win.month, "MMMM yyyy")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.fontScale
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Button
                    Accessible.name: Tr.t("Back to today")
                    MouseArea { anchors.fill: parent; onClicked: win.goToday() }
                    KeyFocus { onActivated: win.goToday() }
                }
                IconButton { icon: "go-next"; size: 28; tip: win.view === "week" ? Tr.t("Next week") : Tr.t("Next month"); onClicked: win.stepView(1) }
            }

            GridLayout {
                visible: win.view === "month"
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

            // ---- week timetable: 7-day grid with hour rows -------------------
            ColumnLayout {
                visible: win.view === "week"
                Layout.fillWidth: true
                spacing: 4
                GridLayout {
                    Layout.fillWidth: true
                    columns: 8
                    rowSpacing: 2
                    columnSpacing: 2
                    Text {
                        text: ""
                        Layout.fillWidth: false
                        Layout.preferredWidth: 44
                        color: Theme.faint
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                    }
                    Repeater {
                        model: win.weekDays
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property date dayDate: win.weekDays[index]
                            readonly property bool isToday: win.isSameDay(dayDate, win.today)
                            readonly property bool isSelected: win.isSameDay(dayDate, win.selectedDate)
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: 8
                            color: isSelected ? Theme.accent : isToday ? Theme.accentSoft : "transparent"
                            Accessible.role: Accessible.Button
                            Accessible.name: Qt.formatDate(dayDate, "dddd d MMMM yyyy") + (isToday ? " (" + Tr.t("today") + ")" : "")
                            Text {
                                anchors.centerIn: parent
                                text: Qt.formatDate(dayDate, "ddd d")
                                color: isSelected ? Theme.accentInk : isToday ? Theme.accent : Theme.text
                                font.family: Theme.font
                                font.pixelSize: 11 * Theme.fontScale
                                font.weight: isSelected || isToday ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.selectWeekDay(parent.index)
                            }
                            KeyFocus { onActivated: win.selectWeekDay(parent.index) }
                        }
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 8
                    rowSpacing: 2
                    columnSpacing: 2
                    Text {
                        text: Tr.t("All-day")
                        Layout.preferredWidth: 44
                        color: Theme.faint
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                        verticalAlignment: Text.AlignVCenter
                    }
                    Repeater {
                        model: 7
                        Rectangle {
                            required property int index
                            readonly property var _evs: win.allDayForDay(index)
                            Layout.fillWidth: true
                            implicitHeight: Math.max(22, _evs.length * 18 + 4)
                            radius: 6
                            color: "transparent"
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 2
                                Repeater {
                                    model: parent._evs
                                    Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 16
                                        radius: 4
                                        color: Theme.accentSoft
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.summary
                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4; anchors.rightMargin: 4
                                            text: modelData.summary
                                            color: Theme.text
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                            font.family: Theme.font
                                            font.pixelSize: 9 * Theme.fontScale
                                        }
                                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.openEditor(modelData) }
                                        KeyFocus { onActivated: win.openEditor(modelData) }
                                    }
                                }
                            }
                        }
                    }
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    contentHeight: hourCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: hourCol
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: 24
                            RowLayout {
                                required property int index
                                readonly property int hour: index
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.preferredWidth: 44
                                    Layout.fillWidth: false
                                    text: (hour < 10 ? "0" : "") + hour + ":00"
                                    color: Theme.faint
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: Theme.font
                                    font.pixelSize: 10 * Theme.fontScale
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Repeater {
                                    model: 7
                                    Rectangle {
                                        required property int index
                                        readonly property var _evs: win.weekEventsForHour(index, parent.hour)
                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(20, _evs.length * 16 + 2)
                                        radius: 4
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.stroke
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            spacing: 1
                                            Repeater {
                                                model: parent._evs.slice(0, 2)
                                                Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    implicitHeight: 14
                                                    radius: 3
                                                    color: Theme.accentSoft
                                                    Accessible.role: Accessible.Button
                                                    Accessible.name: modelData.summary + " " + Qt.formatTime(new Date(modelData.start * 1000), "HH:mm")
                                                    Text {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 3; anchors.rightMargin: 3
                                                        text: modelData.summary
                                                        color: Theme.text
                                                        elide: Text.ElideRight
                                                        verticalAlignment: Text.AlignVCenter
                                                        font.family: Theme.font
                                                        font.pixelSize: 9 * Theme.fontScale
                                                    }
                                                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.openEditor(modelData) }
                                                    KeyFocus { onActivated: win.openEditor(modelData) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: win.weekEvents.length > 0
                    text: Tr.t("%1 in this week").arg(win.weekEvents.length)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
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
                    visible: win.view === "month" && win.monthEvents.length > 0
                    text: Tr.t("%1 in this month").arg(win.monthEvents.length)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Text {
                    visible: win.view === "week" && win.weekEvents.length > 0
                    text: Tr.t("%1 in this week").arg(win.weekEvents.length)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
            }

            TextField {
                id: searchField
                visible: !win.editor
                Layout.fillWidth: true
                placeholder: Tr.t("Search events by title")
                label: Tr.t("Search events by title")
                onTextChanged: { if (text !== Agenda.search) Agenda.search = text; }
            }
            Connections { target: Agenda; function onSearchChanged() { if (Agenda.search !== searchField.text) searchField.text = Agenda.search; } }

            // ---- the day's events (or the editor) --------------------------
            Flickable {
                visible: !win.editor
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
                        model: win.shownEvents
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "x-office-calendar"
                            title: modelData.summary
                            subtitle: Agenda.when(modelData) + (modelData.location ? " · " + modelData.location : "") + (modelData.calendar ? " · " + modelData.calendar : "")
                            onClicked: win.openEditor(modelData)
                        }
                    }
                    EmptyState {
                        visible: win.shownEvents.length === 0
                        icon: "x-office-calendar"
                        title: Agenda.search !== "" ? Tr.t("No matches") : Tr.t("Nothing that day")
                        subtitle: Agenda.search !== "" ? Tr.t("Try another search") : Agenda.available ? Tr.t("No events for this day") : Tr.t("Add a calendar in Settings > Your account")
                        actionText: Agenda.available ? Tr.t("Refresh") : ""
                        onAction: Agenda.refresh()
                    }
                }
            }

            // ---- calendars: enable/disable each EDS source -----------------
            ColumnLayout {
                visible: !win.editor
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Calendars")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        visible: Agenda.lastEnabled !== ""
                        text: Agenda.lastEnabled
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10 * Theme.fontScale
                    }
                    IconButton { icon: "view-refresh"; size: 24; tip: Tr.t("Refresh calendars"); onClicked: { Agenda.refreshCalendars(); Agenda.refreshAccounts(); } }
                }
                ColumnLayout {
                    visible: Agenda.calendars.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(140, calList.implicitHeight + 4)
                    spacing: 2
                    clip: true
                    ColumnLayout {
                        id: calList
                        Layout.fillWidth: true
                        spacing: 2
                        Repeater {
                            model: Agenda.calendars
                            SwitchRow {
                                required property var modelData
                                Layout.fillWidth: true
                                text: modelData.name + (modelData.account ? " · " + modelData.account : "")
                                hint: modelData.enabled ? (modelData.writable ? Tr.t("shown in the grid and this list") : Tr.t("read-only")) : Tr.t("hidden from the grid")
                                checked: !!modelData.enabled
                                onToggled: on => Agenda.setCalendarEnabled(modelData.name, on)
                            }
                        }
                    }
                }
                Text {
                    visible: Agenda.calendarsAvailable && Agenda.calendars.length === 0
                    Layout.fillWidth: true
                    text: Tr.t("No calendars found — add one in Settings > Your account")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Text {
                    visible: !Agenda.calendarsAvailable
                    Layout.fillWidth: true
                    text: Tr.t("Calendar service unavailable")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Text {
                    visible: Agenda.calendarsAvailable && Agenda.calendars.length > 0
                    Layout.fillWidth: true
                    text: Tr.t("New events go to:")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Flow {
                    visible: Agenda.calendarsAvailable && Agenda.calendars.length > 0
                    Layout.fillWidth: true
                    spacing: 6
                    Choice { text: Tr.t("First enabled"); selected: Ui.calendarSelected === ""; onClicked: { Ui.calendarSelected = ""; Agenda.selectedCalendar = ""; } }
                    Repeater {
                        model: win.enabledCalendars
                        Choice {
                            required property var modelData
                            text: modelData.name
                            selected: Ui.calendarSelected === modelData.name
                            onClicked: { Ui.calendarSelected = modelData.name; Agenda.selectedCalendar = modelData.name; }
                        }
                    }
                }
            }

            // ---- online accounts: presentation only -------------------------
            ColumnLayout {
                visible: !win.editor
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Online calendars")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                ColumnLayout {
                    visible: Agenda.accounts.length > 0
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: Agenda.accounts
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "x-office-calendar"
                            title: modelData.name
                            subtitle: (modelData.calendars || []).join(", ")
                            trailing: modelData.enabled ? Tr.t("enabled") : Tr.t("off")
                        }
                    }
                }
                Text {
                    visible: Agenda.accounts.length === 0 && Agenda.calendarsAvailable
                    Layout.fillWidth: true
                    text: Tr.t("No online accounts — local calendars only")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Online calendars sync through GNOME Settings accounts. Adding one opens GNOME Settings accounts; CalDAV sync is not implemented in this shell.")
                    color: Theme.dim
                    wrapMode: Text.WordWrap
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Button {
                    Layout.fillWidth: true
                    text: Tr.t("Open account settings")
                    kind: "outline"
                    onClicked: Agenda.openAccountSettings()
                }
            }

            // ---- create / edit / delete form -------------------------------
            ColumnLayout {
                visible: win.editor
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: win.editingEvent ? Tr.t("Edit event") : Tr.t("New event")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                TextField {
                    id: fTitle
                    Layout.fillWidth: true
                    placeholder: Tr.t("Title")
                    label: Tr.t("Title")
                    onAccepted: win.saveEditor()
                }
                TextField {
                    id: fLocation
                    Layout.fillWidth: true
                    placeholder: Tr.t("Location")
                    label: Tr.t("Location")
                }
                // the calendar this event belongs to: fixed when editing,
                // chosen (Ui.calendarSelected) when new
                Flow {
                    visible: !win.editingEvent
                    Layout.fillWidth: true
                    spacing: 6
                    Choice { text: Tr.t("First enabled"); selected: Ui.calendarSelected === ""; onClicked: { Ui.calendarSelected = ""; Agenda.selectedCalendar = ""; } }
                    Repeater {
                        model: win.enabledCalendars
                        Choice {
                            required property var modelData
                            text: modelData.name
                            selected: Ui.calendarSelected === modelData.name
                            onClicked: { Ui.calendarSelected = modelData.name; Agenda.selectedCalendar = modelData.name; }
                        }
                    }
                }
                Text {
                    visible: win.editingEvent !== null && win.editingEvent.calendar !== undefined
                    Layout.fillWidth: true
                    text: Tr.t("Calendar: %1").arg(win.editingEvent ? win.editingEvent.calendar : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField { id: fDateA; Layout.preferredWidth: 110; placeholder: "2026-11-08"; label: Tr.t("Start date (yyyy-MM-dd)") }
                    TextField { id: fTimeA; Layout.preferredWidth: 70; placeholder: "09:00"; label: Tr.t("Start time (HH:mm)"); enabled: !win.fAllDay }
                    Button { text: win.fAllDay ? Tr.t("All-day: on") : Tr.t("All-day: off"); kind: "outline"; onClicked: win.fAllDay = !win.fAllDay }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField { id: fDateB; Layout.preferredWidth: 110; placeholder: "2026-11-08"; label: Tr.t("End date (yyyy-MM-dd)") }
                    TextField { id: fTimeB; Layout.preferredWidth: 70; placeholder: "10:00"; label: Tr.t("End time (HH:mm)"); enabled: !win.fAllDay }
                }
                Text {
                    visible: win.formError !== ""
                    Layout.fillWidth: true
                    text: win.formError
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button { Layout.fillWidth: true; text: Tr.t("Save"); kind: "primary"; onClicked: win.saveEditor() }
                    Button { Layout.fillWidth: true; text: Tr.t("Cancel"); onClicked: win.closeEditor() }
                    Button { visible: win.editingEvent !== null; text: Tr.t("Delete"); kind: "danger"; onClicked: win.deleteEditor() }
                }
            }

            Button {
                visible: !win.editor
                Layout.fillWidth: true
                text: Tr.t("New event")
                kind: "primary"
                onClicked: win.openEditor(null)
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: win.editor ? Tr.t("Esc closes the form") : Tr.t("Esc closes · title returns to today · click an event to edit it")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: { if (win.editor) win.closeEditor(); else Ui.calendar = false; } }
    Shortcut { sequence: "Ctrl+R"; onActivated: Agenda.refresh() }
}
