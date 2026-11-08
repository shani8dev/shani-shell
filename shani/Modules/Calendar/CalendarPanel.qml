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

    onVisibleChanged: if (visible) Agenda.refresh()

    MouseArea { anchors.fill: parent; onClicked: Ui.calendar = false }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: { if (win.editor) win.closeEditor(); else Ui.calendar = false; } }

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
