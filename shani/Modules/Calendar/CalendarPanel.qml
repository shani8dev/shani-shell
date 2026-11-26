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
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "../../Common/Time.js" as Time
import "../../Common/Month.js" as Month

AppWindow {
    id: win
    property bool addingAccount: false
    property string accountKind: "other"
    appName: "Calendar"
    tools: [
        IconButton { size: Theme.px(30); icon: "view-refresh"; tip: Tr.t("Refresh"); onClicked: win.refresh() },
        IconButton {
            size: Theme.px(30); icon: "document-import"; tip: Tr.t("Import an .ics file")
            onClicked: FilePicker.open({ mode: "open", title: Tr.t("An invitation or calendar file"),
                filters: ["ics", "vcs"],
                onPicked: paths => { if (paths.length) Agenda.importFile(paths[0]); } })
        }
    ]
    visible: Ui.calendar
    onGone: Ui.calendar = false
    margins: 0
    implicitWidth: Theme.px(760)
    implicitHeight: Math.max(320, Math.min(900, col.implicitHeight + 40))
    shortcutSearch: searchField.input  // Ctrl+F focuses the calendar search
    shortcutRefresh: win.refresh       // Ctrl+R reloads the date range
    // blur behind the card, as on every shell surface (ext-background-effect)
    function refresh() { Agenda.refresh(); }

    onVisibleChanged: if (visible) { Agenda.refresh(); win.view = Ui.calendarView || "month"; win.ensureRange(); }
    Connections { target: Ui; function onCalendarViewChanged() { win.view = Ui.calendarView || "month"; } }

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: { if (win.editor) win.closeEditor(); else win.requestClose(); }
        // Keys from the grid's KeyFocus delegates bubble up to here. Arrows move
        // the selection; Home/End/PageUp/PageDown are the calendar conventions.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) return;
            if (win.handleCalendarKey(event.key)) event.accepted = true;
        }
    }

    property date today: new Date()
    property int offset: 0
    property date selectedDate: new Date()
    // month view or week view: synced to Ui.calendarView so the CLI/shell
    // and the surface agree
    property string view: Ui.calendarView || "month"
    // time zone for the times shown: "local" or a zoneinfo name. The QML JS
    // engine's Intl converts; if it is missing we show local time + the label.
    property string zone: "local"
    readonly property var zones: [
        ["local", Tr.t("Local")],
        ["UTC", "UTC"],
        ["America/New_York", "America/New_York"],
        ["Europe/London", "Europe/London"],
        ["Asia/Kolkata", "Asia/Kolkata"],
        ["Asia/Tokyo", "Asia/Tokyo"],
        ["Australia/Sydney", "Australia/Sydney"]
    ]
    readonly property string zoneLabel: {
        const z = zones.find(x => x[0] === zone);
        return z ? z[1] : zone;
    }
    function zoneTime(epochSec) {
        const d = new Date(epochSec * 1000);
        if (zone === "local" || typeof Intl === "undefined")
            return Qt.formatTime(d, "HH:mm");
        try {
            const parts = new Intl.DateTimeFormat("en-GB", { timeZone: zone, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(d);
            const h = (parts.find(p => p.type === "hour") || {}).value || "00";
            const m = (parts.find(p => p.type === "minute") || {}).value || "00";
            return h + ":" + m;
        } catch (e) {
            return Qt.formatTime(d, "HH:mm");   // unsupported zone/Intl: local time
        }
    }
    // a minute tick keeps the current-time line honest (and the today marker)
    Timer { interval: 60000; running: true; repeat: true; onTriggered: win.today = new Date() }
    function isNowHour(h) {
        return win.offset === 0 && win.isSameDay(new Date(), win.selectedDate)
            && new Date().getHours() === h;
    }
    function nowFraction() {
        const n = new Date();
        return (n.getMinutes() + n.getSeconds() / 60) / 60;
    }
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property date weekAnchor: new Date(today.getFullYear(), today.getMonth(), today.getDate() + (offset * 7))
    readonly property bool sundayFirst: Settings.data.weekStartsOn === "sunday"
    // blanks before the 1st, then the days; Monday-first or Sunday-first
    readonly property int lead: Month.lead(month, sundayFirst)
    readonly property int days: Month.daysIn(month)
    readonly property bool weekNumbers: Settings.data.weekNumbers
    // day numbers for one month of the year view: leading blanks, then 1..N
    function yearMonthDays(y, m) {
        const out = [];
        const lead = Month.lead(new Date(y, m, 1), sundayFirst);
        for (let i = 0; i < lead; i++) out.push(0);
        const count = new Date(y, m + 1, 0).getDate();
        for (let d = 1; d <= count; d++) out.push(d);
        return out;
    }
    // the grid, cell by cell: an optional week number, then seven days, per row
    // (Common/Month.js, shared with the date picker and the sidebar calendar)
    readonly property var cells: Month.cells(month, sundayFirst, weekNumbers)
    readonly property var weekNames: Month.weekNames(sundayFirst, Tr.dayNamesShort)

    function isSameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function eventsOnDay(day) {
        return Agenda.events.filter(e => {
            const s = new Date(e.start * 1000);
            return s.getFullYear() === month.getFullYear() && s.getMonth() === month.getMonth() && s.getDate() === day;
        });
    }
    function hasEvents(day) { return eventsOnDay(day).length > 0; }
    // EDS events carry no "type": a holiday is an event on a calendar whose name
    // says so (the usual "Holidays" subscription); every other event is a
    // reminder. The cell paints both, as the CuboCore calendar plugin does.
    readonly property int cellDotCap: 3
    function isHolidayEvent(e) { return /holiday/i.test(String(e.calendar || "")); }
    function cellReminders(day) { return eventsOnDay(day).filter(e => !isHolidayEvent(e)); }
    function cellHolidays(day) { return eventsOnDay(day).filter(e => isHolidayEvent(e)); }
    function cellDotCount(day) { return Math.min(cellDotCap, cellReminders(day).length); }
    function cellOverflow(day) { return Math.max(0, cellReminders(day).length - cellDotCap); }
    function cellA11yName(day) {
        if (day <= 0) return "";
        let s = Qt.formatDate(new Date(month.getFullYear(), month.getMonth(), day), "dddd d MMMM yyyy");
        const r = cellReminders(day).length, h = cellHolidays(day).length;
        if (r || h) s += ", " + Tr.t("has events");
        if (r) s += ", " + Tr.t("Reminders") + ": " + r;
        if (h) s += ", " + Tr.t("Holiday") + ": " + h;
        return s;
    }
    // title search lives on Agenda (so IPC `calendarSearch` uses the same box)
    readonly property var dayEvents: Agenda.events.filter(e => isSameDay(new Date(e.start * 1000), selectedDate))
    // GNOME Calendar / KOrganizer search the whole event, not just its title:
    // a place or a word in the notes is often what you remember.
    readonly property var shownEvents: dayEvents.filter(e => {
        const needle = Agenda.search.toLowerCase();
        return needle === "" || ["summary", "location", "description"].some(k =>
            String(e[k] || "").toLowerCase().indexOf(needle) >= 0);
    })
    // GNOME/KDE/Apple search the whole calendar, not only the selected day;
    // every typed word must match somewhere in the event.
    readonly property bool searchActive: Agenda.search.trim() !== ""
    readonly property var searchTerms: Agenda.search.toLowerCase().trim().split(/\s+/).filter(t => t !== "")
    readonly property var searchResults: searchTerms.length === 0 ? [] : Agenda.events.filter(e => {
        const hay = ["summary", "location", "description"].map(k => String(e[k] || "").toLowerCase()).join(" ");
        return searchTerms.every(t => hay.indexOf(t) >= 0);
    })
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
    // an imported invitation: its day (its month first)
    Connections {
        target: Agenda
        function onShowDay(when) {
            const d = new Date(when);
            win.offset = (d.getFullYear() - win.today.getFullYear()) * 12 + d.getMonth() - win.today.getMonth();
            win.selectedDate = d;
        }
    }
    function goToday() {
        offset = 0;
        selectedDate = new Date();
    }
    // Arrow keys step one day / one week; keep the shown period containing the
    // new selection instead of leaving a selected day off screen.
    function stepSelected(delta) {
        const d = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + delta);
        selectedDate = d;
        if (view === "day") {
            offset = (d.getFullYear() - today.getFullYear()) * 12 + d.getMonth() - today.getMonth();
        } else if (view === "week") {
            const days = Math.round((d - weekStart) / 86400000);
            if (days < 0) offset += Math.ceil(days / 7);
            else if (days >= 7) offset += Math.floor(days / 7);
        } else if (view === "year") {
            if (d.getFullYear() !== month.getFullYear()) offset += d.getFullYear() - month.getFullYear();
        } else {
            const dm = (d.getFullYear() - month.getFullYear()) * 12 + d.getMonth() - month.getMonth();
            if (dm !== 0) offset += dm;
        }
    }
    function selectMonthEnd() {
        if (view === "week") selectedDate = weekDays[6];
        else if (view === "year") selectedDate = new Date(month.getFullYear(), 11, 31);
        else selectedDate = new Date(month.getFullYear(), month.getMonth() + 1, 0);
    }
    function handleCalendarKey(key) {
        if (win.editor || win.viewing) return false;
        switch (key) {
            case Qt.Key_Left:  win.stepSelected(-1); return true;
            case Qt.Key_Right: win.stepSelected(1);  return true;
            case Qt.Key_Up:    win.stepSelected(-7); return true;
            case Qt.Key_Down:  win.stepSelected(7);  return true;
            case Qt.Key_Home:  win.goToday(); return true;
            case Qt.Key_End:   win.selectMonthEnd(); return true;
            case Qt.Key_PageUp:   win.stepView(-1); return true;
            case Qt.Key_PageDown: win.stepView(1); return true;
        }
        return false;
    }
    property bool pickingDate: false
    // Jump straight to a date: paging twelve months to reach last February
    // is not what a calendar app does.
    function goToDate(text) {
        const m = String(text || "").trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
        if (!m) return false;
        const y = Number(m[1]), mo = Number(m[2]) - 1, d = Number(m[3]);
        const dt = new Date(y, mo, d);
        if (dt.getFullYear() !== y || dt.getMonth() !== mo || dt.getDate() !== d) return false;
        if (view === "week") {
            const a = new Date(today.getFullYear(), today.getMonth(), today.getDate());
            offset = Math.round((dt - a) / (7 * 86400000));
        } else
            offset = (dt.getFullYear() - today.getFullYear()) * 12 + dt.getMonth() - today.getMonth();
        selectedDate = dt;
        pickingDate = false;
        return true;
    }
    function selectDay(day) {
        selectedDate = new Date(month.getFullYear(), month.getMonth(), day);
    }
    function stepView(delta) {
        if (view === "week" || view === "agenda")
            offset += delta;
        else if (view === "year")
            offset += delta * 12;
        else if (view === "day") {
            const d = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + delta);
            selectedDate = d;
            offset = (d.getFullYear() - today.getFullYear()) * 12 + d.getMonth() - today.getMonth();
        } else
            stepMonth(delta);   // keep the selected day inside the shown month
    }
    function viewLabel() {
        if (view === "agenda") return Tr.t("Agenda");
        if (view === "week") return weekLabel;
        if (view === "year") return String(month.getFullYear());
        if (view === "day") return Qt.formatDate(selectedDate, "dddd d MMMM yyyy");
        return Qt.formatDate(month, "MMMM yyyy");
    }
    function prevTip() {
        if (view === "week" || view === "agenda") return Tr.t("Previous week");
        if (view === "day") return Tr.t("Previous day");
        if (view === "year") return Tr.t("Previous year");
        return Tr.t("Previous month");
    }
    function nextTip() {
        if (view === "week" || view === "agenda") return Tr.t("Next week");
        if (view === "day") return Tr.t("Next day");
        if (view === "year") return Tr.t("Next year");
        return Tr.t("Next month");
    }
    function selectYearDay(y, m, d) {
        selectedDate = new Date(y, m, d);
        Ui.calendarView = "day";
        view = "day";
    }
    // Fetch exactly the window on screen. Agenda merges it into a date-keyed
    // cache, so stepping weeks/months/years stops showing empty grids.
    function ensureRange() {
        let from, to;
        if (view === "year") {
            from = new Date(month.getFullYear(), 0, 1);
            to = new Date(month.getFullYear() + 1, 0, 1);
        } else if (view === "month") {
            from = new Date(month.getFullYear(), month.getMonth(), 1);
            to = new Date(month.getFullYear(), month.getMonth() + 1, 1);
        } else if (view === "agenda") {
            // two weeks behind and four ahead: "Earlier" must have real content
            const a = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 14 + offset * 7);
            from = a;
            to = new Date(a.getFullYear(), a.getMonth(), a.getDate() + 42);
        } else {  // day and week both show a week at a time
            from = weekStart;
            to = new Date(weekDays[6].getFullYear(), weekDays[6].getMonth(), weekDays[6].getDate() + 1);
        }
        Agenda.loadRange(from, to);
    }
    Connections {
        target: win
        function onOffsetChanged() { win.ensureRange(); }
        function onSelectedDateChanged() { win.ensureRange(); }
        function onViewChanged() { win.ensureRange(); }
    }
    // A hidden event in an overfull hour: show its whole day, where all of them fit.
    function openDayFromWeek(col) {
        selectWeekDay(col);
        Ui.calendarView = "day";
        view = "day";
    }
    // EDS calendar colours are arbitrary strings; fall back rather than assign
    // an invalid color to a typed property.
    function eventColor(cal) {
        const c = Agenda.colorOf(cal);
        if (!c) return Theme.accent;
        try { Qt.color(c); return c; } catch (e) { return Theme.accent; }
    }
    // An all-day event has its own date; it is not necessarily "Today".
    function detailWhen(e) {
        if (!e || !e.start) return "";
        const day = Qt.formatDate(new Date(e.start * 1000), "ddd d MMM yyyy");
        return e.allDay ? day + " · " + Tr.t("All day")
                        : day + " · " + win.zoneTime(e.start) + " – " + win.zoneTime(e.end || 0);
    }
    // ---- event -> note (both surfaces own plain files, no new store) --------
    property string pendingNoteName: ""
    property string pendingNoteBody: ""
    function eventNoteName(e) {
        const n = QuickNotes.valid((e || {}).summary || "");
        return n === "" ? Tr.t("Event") : n;
    }
    function isoDay(ms) {
        return Time.dayKey(new Date(ms));
    }
    function eventNoteBody(e) {
        const ev = e || {};
        const title = String(ev.summary || "").trim() || Tr.t("Event");
        let body = "# " + title + "\n\n- Date: [[" + win.isoDay(Number(ev.start || 0) * 1000) + "]]\n";
        if (ev.location) body += "- Location: " + ev.location + "\n";
        if (ev.description) body += "\n" + ev.description + "\n";
        return body;
    }
    function noteForEvent(e) {
        if (!e) return;
        const name = win.eventNoteName(e);
        Ui.openNotes();
        // a note with the same name is opened, never overwritten
        if (QuickNotes.notes.some(n => n.name === name && n.notebook === "")) {
            QuickNotes.open(name, "");
            return;
        }
        win.pendingNoteName = name;
        win.pendingNoteBody = win.eventNoteBody(e);
        QuickNotes.create(name, "");
        noteFill.restart();
    }
    // shortcut: FileView loads the new file asynchronously; 800 ms is enough
    // on local disk, but a load signal from QuickNotes would be more reliable
    Timer {
        id: noteFill
        interval: 800
        onTriggered: {
            if (QuickNotes.current !== win.pendingNoteName || win.pendingNoteBody === "") return;
            QuickNotes.set(win.pendingNoteBody);
            win.pendingNoteBody = "";
        }
    }

    // the week on screen: seven days from its first, which follows "week starts on"
    readonly property date weekStart: new Date(weekAnchor.getFullYear(), weekAnchor.getMonth(),
        weekAnchor.getDate() - (sundayFirst ? weekAnchor.getDay() : (weekAnchor.getDay() + 6) % 7))
    readonly property var weekDays: Array.from({ length: 7 }, (_, i) => new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + i))
    readonly property string weekLabel: Qt.formatDate(weekDays[0], "d MMM") + " – " + Qt.formatDate(weekDays[6], "d MMM yyyy")
    readonly property var weekEvents: {
        const a = weekDays[0], b = new Date(a.getFullYear(), a.getMonth(), a.getDate() + 7);
        return Agenda.events.filter(e => { const s = new Date(e.start * 1000); return s >= a && s < b; });
    }
    function eventsOn(col) { return weekEvents.filter(e => isSameDay(new Date(e.start * 1000), weekDays[col])); }
    function allDayForDay(col) { return eventsOn(col).filter(e => e.allDay); }
    function weekEventsForHour(col, hour) { return eventsOn(col).filter(e => !e.allDay && new Date(e.start * 1000).getHours() === hour); }
    function selectWeekDay(col) { selectedDate = weekDays[col]; }
    function dayEventsForHour(hour) { return shownEvents.filter(e => !e.allDay && new Date(e.start * 1000).getHours() === hour); }

    function isReadOnly(e) {
        if (!e) return false;
        const cal = Agenda.calendars.find(c => c.name === e.calendar);
        return !!(cal && cal.readOnly);
    }
    // Drag a chip onto another day / hour. Only the date changes: duration,
    // calendar, guests, repeat, alarm and zone travel with the event.
    function moveEventTo(e, day, hour, asAllDay) {
        if (!e || win.isReadOnly(e)) {
            formError = Tr.t("That calendar is read-only — the event was not moved");
            return;
        }
        const allDay = asAllDay === true ? true : !!e.allDay;
        const dur = Math.max(3600, (e.end || (e.start + 3600)) - e.start);
        const s = new Date(e.start * 1000);
        const ns = allDay
            ? new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime() / 1000
            : new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, s.getMinutes()).getTime() / 1000;
        Agenda.editEvent({ uid: e.uid, summary: e.summary || "", start: ns, end: ns + dur,
            location: e.location || "", description: e.description || "", rrule: e.rrule || "",
            alarm: Number(e.alarm || 0), timezone: e.timezone || "", attendees: e.attendees || [],
            allDay: allDay, calendar: e.calendar || "" });
        formError = "";
        Agenda.refresh();
    }
    // An agenda row shows the event's day first, then its detail sheet.
    function showDayOf(e) {
        if (!e) return;
        Ui.calendarView = "day";
        win.view = "day";
        win.goToDate(Qt.formatDate(new Date(e.start * 1000), "yyyy-MM-dd"));
    }
    // The agenda's "Earlier" section is the overdue list: events that ended,
    // newest first, inside the window ensureRange() just loaded.
    property bool showEarlier: true
    readonly property var agendaUpcoming: Agenda.events.filter(e => (e.end || e.start) * 1000 > Date.now())
    readonly property var agendaEarlier: Agenda.events.filter(e => (e.end || e.start) * 1000 <= Date.now()).slice(-12).reverse()

    // ---- event editor ------------------------------------------------------
    property bool editor: false
    property var editingEvent: null     // the event being edited, null = new
    property bool fAllDay: false
    property string fSavedTimeA: ""     // clock put aside while all-day is on
    property string fSavedTimeB: ""
    property string formError: ""
    property bool confirmDelete: false  // deleting is a two-step, deliberate action
    property string quickError: ""
    // click to view first; the edit form is a deliberate second step
    property bool viewing: false
    property var viewingEvent: null
    // repeat / end-repeat and this event's own reminder and zone
    property string fRepeat: "NONE"     // NONE | DAILY | WEEKLY | MONTHLY | YEARLY
    property int fRepeatInterval: 1     // every N days/weeks/months/years
    property string fByDay: ""          // MO,TU,… for a weekly repeat
    readonly property var repeatDays: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    property string fRepeatUntil: ""    // yyyy-MM-dd
    property bool repeatTouched: false  // the person edited the repeat controls
    // a richer rule is kept verbatim, but say so rather than hide the controls
    readonly property bool complexRule: {
        const r = String((win.viewingEvent || win.editingEvent)?.rrule || "").toUpperCase();
        return r !== "" && !win.repeatTouched && /(COUNT|BYMONTHDAY|BYSETPOS|BYMONTH|WKST)/.test(r);
    }
    property int fAlarm: 0              // minutes before; 0 = no alarm
    property string fZone: "local"
    readonly property bool readOnlyEvent: win.isReadOnly(win.editingEvent || win.viewingEvent)

    function viewEvent(e) {
        if (!e) return;
        win.viewingEvent = e;
        win.viewing = true;
        win.editor = false;
    }
    function editViewed() {
        const e = win.viewingEvent;
        win.viewing = false;
        win.viewingEvent = null;
        win.openEditor(e);
    }
    // The form owns FREQ, INTERVAL, BYDAY and UNTIL. If the event had a richer
    // RRULE (COUNT, BYMONTHDAY …) and the person did not touch the repeat
    // controls, return the original verbatim instead of silently flattening it.
    function ruleFromForm() {
        if (win.fRepeat === "NONE") return "";
        const built = "FREQ=" + win.fRepeat + ";INTERVAL=" + Math.max(1, Math.min(99, win.fRepeatInterval)) +
            (win.fRepeat === "WEEKLY" && win.fByDay !== "" ? ";BYDAY=" + win.fByDay : "") +
            (win.fRepeatUntil !== "" ? ";UNTIL=" + win.fRepeatUntil.replace(/-/g, "") + "T235959" : "");
        const original = String((win.viewingEvent || win.editingEvent)?.rrule || "");
        if (original !== "" && !win.repeatTouched) return original;
        return built;
    }
    function formFromRule(rule) {
        const r = String(rule || "").toUpperCase();
        const f = r.match(/FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)/);
        win.fRepeat = f ? f[1] : "NONE";
        const iv = r.match(/INTERVAL=(\d+)/);
        win.fRepeatInterval = iv ? Math.max(1, Math.min(99, Number(iv[1]))) : 1;
        const bd = r.match(/BYDAY=((?:MO|TU|WE|TH|FR|SA|SU)(?:,(?:MO|TU|WE|TH|FR|SA|SU))*)/);
        win.fByDay = bd ? bd[1] : "";
        const u = r.match(/UNTIL=(\d{8})/);
        win.fRepeatUntil = u ? u[1].slice(0, 4) + "-" + u[1].slice(4, 6) + "-" + u[1].slice(6, 8) : "";
        win.repeatTouched = false;  // a fresh edit form starts from the event's rule
    }
    function toggleRepeatDay(day) {
        const days = win.fByDay ? win.fByDay.split(",") : [];
        const i = days.indexOf(day);
        if (i >= 0) days.splice(i, 1);
        else days.push(day);
        win.fByDay = days.sort((a, b) => win.repeatDays.indexOf(a) - win.repeatDays.indexOf(b)).join(",");
        win.repeatTouched = true;
    }

    function _fmtDate(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }
    function _fmtTime(d) { return Qt.formatTime(d, "HH:mm"); }
    function openEditor(e) {
        editingEvent = e || null;
        formError = "";
        confirmDelete = false;
        if (e) {
            const s = new Date(e.start * 1000), en = new Date(e.end * 1000);
            fTitle.text = e.summary || "";
            fLocation.text = e.location || "";
            fAttendees.text = (e.attendees || []).join(", ");
            fDescription.text = e.description || "";
            formFromRule(e.rrule);
            fAlarm = Number(e.alarm || 0);
            fZone = e.timezone || "local";
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
            fAttendees.text = "";
            fDescription.text = "";
            formFromRule("");
            fAlarm = 0;
            fZone = "local";
            fDateA.text = _fmtDate(s);
            fTimeA.text = _fmtTime(s);
            fDateB.text = _fmtDate(en);
            fTimeB.text = _fmtTime(en);
            fAllDay = false;
        }
        fSavedTimeA = fTimeA.text;
        fSavedTimeB = fTimeB.text;
        editor = true;
    }
    function closeEditor() { editor = false; formError = ""; confirmDelete = false; }
    // Switching an event between all-day and timed must not destroy its clock:
    // stash it while the all-day toggle uses 00:00–23:59, then put it back.
    function toggleAllDay() {
        if (fAllDay) {
            fTimeA.text = fSavedTimeA !== "" ? fSavedTimeA : "09:00";
            fTimeB.text = fSavedTimeB !== "" ? fSavedTimeB : "10:00";
            fAllDay = false;
        } else {
            fSavedTimeA = fTimeA.text;
            fSavedTimeB = fTimeB.text;
            fTimeA.text = "00:00";
            fTimeB.text = "23:59";
            fAllDay = true;
        }
    }
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
    // Natural language parser: "lunch Friday at noon", "meeting tomorrow at 3pm",
    // "team call next tuesday 2:30pm", etc. Returns epoch seconds or NaN.
    // Relative words are anchored on the selected day (GNOME Calendar's quick
    // add does the same), not on a hidden "now" that may be months away.
    function _parseNaturalDateTime(text, anchor) {
        const s = String(text || "").trim();
        if (s === "")
            return NaN;
        const base = anchor instanceof Date ? anchor : selectedDate;
        // Match an ISO date first
        const iso = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
        if (iso) {
            const t = s.match(/(\d{1,2}):(\d{2})/);
            return _parseDateTime(iso[0], t ? Time.clockPadded(t[1] + ":" + t[2]) : "00:00");
        }
        // Now/today/tomorrow
        let dayOffset = 0;
        if (/^today/i.test(s)) dayOffset = 0;
        else if (/^tomorrow/i.test(s)) dayOffset = 1;
        else if (/^yesterday/i.test(s)) dayOffset = -1;
        // Next/this/last + weekday
        const weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
        let wdMatch = s.match(/(?:next|this|last)\s+(?:the\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)/i);
        if (!wdMatch)
            wdMatch = s.match(/(?:on\s+|at\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b/i);
        let targetDay = -1;
        if (wdMatch) {
            const wd = weekdays.indexOf(wdMatch[1].toLowerCase());
            if (wd >= 0) {
                targetDay = base.getDay();
                const diff = (wd - targetDay + 7) % 7;
                if (/^next/i.test(s)) dayOffset = diff + 7;
                else if (/^last/i.test(s)) dayOffset = diff - 7;
                else dayOffset = diff;
            }
        }
        // "in N days/weeks"
        const inMatch = s.match(/in\s+(\d+)\s+(day|week|month)/i);
        if (inMatch) {
            const n = parseInt(inMatch[1]);
            const unit = inMatch[2].toLowerCase();
            const d = new Date(base.getTime());
            if (unit === "week") d.setDate(d.getDate() + n * 7);
            else if (unit === "month") d.setMonth(d.getMonth() + n);
            else d.setDate(d.getDate() + n);
            // set time
            const t = s.match(/(\d{1,2}):(\d{2})/);
            d.setHours(t ? parseInt(t[1]) : 12, t ? parseInt(t[2]) : 0, 0, 0);
            return Math.floor(d.getTime() / 1000);
        }
        if (targetDay < 0 && dayOffset === 0) {
            // No specific date info — return NaN
            return NaN;
        }
        // Compute the date
        const d = new Date(base.getTime());
        d.setDate(d.getDate() + dayOffset);
        d.setHours(0, 0, 0, 0);
        // Extract time: "at 3pm", "at 3:30pm", "noon", "5:30", "5pm", "3:00"
        let h = -1, mi = 0;
        const pmRe = s.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
        if (pmRe) {
            const numH = parseInt(pmRe[1]);
            const numMi = pmRe[2] ? parseInt(pmRe[2]) : 0;
            let ampm = (pmRe[3] || "").toLowerCase();
            h = numH; mi = numMi;
            if (ampm === "pm" && h < 12) h += 12;
            else if (ampm === "am" && h === 12) h = 0;
        } else {
            const noonRe = s.match(/\bnoon\b/i);
            const midnightRe = s.match(/\bmidnight\b/i);
            if (noonRe) h = 12;
            else if (midnightRe) h = 0;
        }
        if (h < 0) {
            if (fAllDay) h = 0;
            else h = 10;  // default 10am if "lunch"
        }
        d.setHours(h, mi, 0, 0);
        return Math.floor(d.getTime() / 1000);
    }
    function saveEditor() {
        if (win.readOnlyEvent) {
            formError = Tr.t("Calendar: %1").arg((win.editingEvent || {}).calendar || "") + " — " + "read-only";
            return;
        }
        const title = fTitle.text.trim();
        if (title === "") {
            formError = Tr.t("An event needs a title");
            return;
        }
        const start = _parseDateTime(fDateA.text, fTimeA.text);
        const end = _parseDateTime(fDateB.text, fTimeB.text);
        // Try natural language parsing as a fallback
        const natStart = isNaN(start) ? _parseNaturalDateTime(fTitle.text + " " + fDateA.text + " " + fTimeA.text, selectedDate) : start;
        const natEnd = isNaN(end) ? _parseNaturalDateTime(fTitle.text + " " + fDateB.text + " " + fTimeB.text, selectedDate) : end;
        if (isNaN(natStart) || isNaN(natEnd) || natEnd <= natStart) {
            formError = Tr.t("Check the dates and times (end after start)");
            return;
        }
        const payload = {
            summary: title,
            start: natStart,
            end: natEnd,
            location: fLocation.text.trim(),
            description: fDescription.text.trim(),
            rrule: win.ruleFromForm(),
            alarm: win.fAlarm,
            timezone: win.fZone === "local" ? "" : win.fZone,
            attendees: fAttendees.text.split(",").map(s => s.trim()).filter(s => s !== ""),
            allDay: fAllDay,
            calendar: editingEvent && editingEvent.calendar ? editingEvent.calendar : Agenda.selectedCalendar,
            uid: editingEvent && editingEvent.uid ? editingEvent.uid : ""
        };
        if (editingEvent)
            Agenda.editEvent(payload);
        else
            Agenda.addEvent(payload);
        closeEditor();
        Agenda.refresh();
    }
    // Quick add fails loudly: an unparsed phrase used to vanish without a word.
    function quickAdd(text) {
        const entry = String(text || "").trim();
        if (entry === "") {
            quickError = Tr.t("Type something like “lunch Friday at noon”");
            return false;
        }
        const start = _parseNaturalDateTime(entry, selectedDate);
        if (isNaN(start)) {
            quickError = Tr.t("Could not read a date — try “meeting tomorrow at 3pm” or yyyy-MM-dd");
            return false;
        }
        quickError = "";
        Agenda.addEvent({ summary: entry, start: start, end: start + 3600,
            location: "", attendees: [], allDay: false,
            calendar: Agenda.selectedCalendar || "", uid: "" });
        return true;
    }
    function deleteEditor() {
        if (!editingEvent || win.readOnlyEvent)
            return;
        if (!win.confirmDelete) {
            win.confirmDelete = true;
            formError = Tr.t("Click Delete again to remove this event");
            return;
        }
        Agenda.deleteEvent({ summary: editingEvent.summary, start: editingEvent.start, end: editingEvent.end,
            location: editingEvent.location, allDay: editingEvent.allDay,
            calendar: editingEvent.calendar, uid: editingEvent.uid });
        closeEditor();
        Agenda.refresh();
    }

    Item {
        id: card
        anchors.fill: parent
        focus: win.visible
        // Key events from the grid's delegates bubble up to the card. Escape is
        // left to the window Shortcut so the detail sheet closes from anywhere.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) return;
            if (win.handleCalendarKey(event.key)) event.accepted = true;
        }
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(12)

            // Quick add: "lunch Friday at noon" -> one-hour event. The full
            // form below is still there for location, guests and calendars.
            TextField {
                Layout.fillWidth: true
                visible: !win.editor
                placeholder: Tr.t("Quick add — “lunch Friday at noon”, Enter to save")
                label: Tr.t("Quick add")
                error: win.quickError
                onTextChanged: win.quickError = ""
                onAccepted: { if (win.quickAdd(text)) clear(); }
            }

            // a Flow: on a phone the chips wrap instead of running off the edge
            Flow {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Choice { text: Tr.t("Month"); selected: win.view === "month"; onClicked: { Ui.calendarView = "month"; Agenda.refresh(); } }
                Choice { text: Tr.t("Week"); selected: win.view === "week"; onClicked: { Ui.calendarView = "week"; Agenda.refresh(); } }
                Choice { text: Tr.t("Day"); selected: win.view === "day"; onClicked: { Ui.calendarView = "day"; Agenda.refresh(); } }
                Choice { text: Tr.t("Year"); selected: win.view === "year"; onClicked: { Ui.calendarView = "year"; Agenda.refresh(); } }
                Choice {
                    text: Tr.t("Agenda")
                    selected: win.view === "agenda"
                    Accessible.name: Tr.t("Agenda: upcoming and earlier events")
                    onClicked: { Ui.calendarView = "agenda"; Agenda.refresh(); }
                }
                Choice {
                    text: Moon.glyph(win.today) + " " + Tr.t("Panchang")
                    selected: false
                    onClicked: {
                        Ui.kundaliDate = Qt.formatDate(win.today, "yyyy-MM-dd");
                        Ui.closeAll();
                        Ui.kundali = true;
                    }
                }
                Choice { text: Tr.t("Go to date…"); selected: win.pickingDate; onClicked: { win.pickingDate = !win.pickingDate; if (win.pickingDate) dateField.forceActiveFocus(); } }
                Choice { text: Tr.t("Today"); onClicked: { win.goToday(); win.pickingDate = false; } }
                Button {
                    visible: !win.editor
                    text: Tr.t("New event")
                    Accessible.name: Tr.t("New event")
                    kind: "primary"
                    onClicked: win.openEditor(null)
                }
            }

            // time zone of the event times shown below
            Flow {
                visible: !win.editor
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: win.zones
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.zone === modelData[0]
                        onClicked: win.zone = modelData[0]
                    }
                }
            }
            Text {
                visible: !win.editor
                Layout.fillWidth: true
                text: Tr.t("Times shown in %1").arg(win.zoneLabel)
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.type("caption")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                IconButton { icon: "go-previous"; size: Theme.px(28); tip: win.prevTip(); onClicked: win.stepView(-1) }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: win.viewLabel()
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type("heading")
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Button
                    Accessible.name: Tr.t("Back to today")
                    MouseArea { anchors.fill: parent; onClicked: win.goToday() }
                    KeyFocus { onActivated: win.goToday() }
                }
                IconButton { icon: "go-next"; size: Theme.px(28); tip: win.nextTip(); onClicked: win.stepView(1) }
            }

            // Read failures are not the same as an empty calendar: say why.
            Rectangle {
                visible: !win.editor && Agenda.loadError !== ""
                Layout.fillWidth: true
                implicitHeight: loadErrText.implicitHeight + Theme.px(10)
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.danger
                Text {
                    id: loadErrText
                    anchors { fill: parent; margins: Theme.px(5) }
                    wrapMode: Text.Wrap
                    text: Agenda.loadError
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
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
                    font.pixelSize: Theme.type("caption")
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
                        font.pixelSize: Theme.type("caption")
                    }
                }
                Repeater {
                    model: win.cells
                    DayCell {
                        id: monthCell
                        required property var modelData
                        readonly property int day: isWeek ? 0 : modelData.day
                        Layout.fillWidth: true
                        implicitHeight: Math.max(Theme.touchTarget, Theme.px(30))
                        isWeek: modelData.week !== undefined
                        label: isWeek ? String(modelData.week) : (day > 0 ? String(day) : "")
                        isToday: day === win.today.getDate() && win.offset === 0 && win.month.getMonth() === win.today.getMonth() && win.month.getFullYear() === win.today.getFullYear()
                        isSelected: !isWeek && day === win.selectedDate.getDate() && win.selectedDate.getMonth() === win.month.getMonth() && win.selectedDate.getFullYear() === win.month.getFullYear()
                        // the spoken name carries the day's reminders and holidays
                        Accessible.name: isWeek ? Tr.t("Week %1").arg(modelData.week) : win.cellA11yName(day)
                        onActivated: win.selectDay(day)
                        Row {
                            // compact markers painted into the day cell itself;
                            // decorative — the cell's Accessible.name carries it
                            id: cellMarkers
                            visible: !monthCell.isWeek && (win.cellReminders(monthCell.day).length > 0 || win.cellHolidays(monthCell.day).length > 0)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.px(2)
                            spacing: Theme.px(2)
                            Accessible.ignored: true
                            Repeater {
                                model: win.cellDotCount(monthCell.day)
                                Rectangle {
                                    width: Theme.px(5); height: Theme.px(5)
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: width / 2
                                    color: monthCell.isSelected ? Theme.accentInk : Theme.accent
                                    Accessible.ignored: true
                                }
                            }
                            Text {
                                visible: win.cellOverflow(monthCell.day) > 0
                                text: "+" + win.cellOverflow(monthCell.day)
                                color: monthCell.isSelected ? Theme.accentInk : Theme.accent
                                font.family: Theme.font
                                font.pixelSize: Theme.px(8) * Theme.fontScale
                                Accessible.ignored: true
                            }
                            Rectangle {
                                visible: win.cellHolidays(monthCell.day).length > 0
                                width: Theme.px(5); height: Theme.px(5)
                                anchors.verticalCenter: parent.verticalCenter
                                rotation: 45
                                color: monthCell.isSelected ? Theme.accentInk : Theme.amber
                                Accessible.ignored: true
                            }
                        }
                    }
                }
            }
            Text {
                // legend for the cell markers above (the day cell is clickable)
                visible: win.view === "month"
                Layout.fillWidth: true
                text: "● " + Tr.t("Reminders") + "    ◆ " + Tr.t("Holidays") + "    +n " + Tr.t("more")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.type("caption")
            }

            // ---- week timetable: 7-day grid with hour rows -------------------
            ColumnLayout {
                visible: win.view === "week"
                Layout.fillWidth: true
                spacing: Theme.px(4)
                GridLayout {
                    Layout.fillWidth: true
                    columns: 8
                    rowSpacing: 2
                    columnSpacing: 2
                    Text {
                        text: ""
                        Layout.fillWidth: false
                        Layout.preferredWidth: win.compact ? Theme.px(30) : Theme.px(44)
                        Layout.maximumWidth: win.compact ? Theme.px(30) : Theme.px(44)
                        color: Theme.faint
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: Theme.type("caption")
                    }
                    Repeater {
                        model: win.weekDays
                        DayCell {
                            required property var modelData
                            required property int index
                            readonly property date dayDate: win.weekDays[index]
                            Layout.fillWidth: true
                            implicitHeight: Math.max(Theme.touchTarget, Theme.px(34))
                            label: Qt.formatDate(dayDate, "ddd d")
                            date: dayDate
                            isToday: win.isSameDay(dayDate, win.today)
                            isSelected: win.isSameDay(dayDate, win.selectedDate)
                            onActivated: win.selectWeekDay(index)
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
                        Accessible.name: Tr.t("All-day")
                        elide: Text.ElideRight
                        Layout.preferredWidth: win.compact ? Theme.px(30) : Theme.px(44)
                        Layout.maximumWidth: win.compact ? Theme.px(30) : Theme.px(44)
                        color: Theme.faint
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: Theme.type("caption")
                        verticalAlignment: Text.AlignVCenter
                    }
                    Repeater {
                        model: 7
                        Rectangle {
                            id: allDayCell
                            required property int index
                            readonly property var _evs: win.allDayForDay(index)
                            Layout.fillWidth: true
                            implicitHeight: Math.max(Theme.touchTarget, _evs.length * Math.max(Theme.touchTarget, Theme.px(16)) + 4)
                            radius: Theme.px(6)
                            color: "transparent"
                            // drop here to make the dragged event all-day
                            DropArea {
                                anchors.fill: parent
                                keys: ["shani-event"]
                                onDropped: {
                                    const e = drag.source && drag.source.dragEvent;
                                    if (e) win.moveEventTo(e, win.weekDays[allDayCell.index], 0, true);
                                    drop.acceptProposedAction();
                                }
                            }
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 2
                                Repeater {
                                    model: allDayCell._evs
                                    Rectangle {
                                        required property var modelData
                                        readonly property color calColor: win.eventColor(modelData.calendar)
                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(Theme.touchTarget, Theme.px(16))
                                        radius: Theme.px(4)
                                        color: Theme.alpha(calColor, 0.45)
                                        property var dragEvent: modelData
                                        Drag.active: chipDrag.drag.active
                                        Drag.keys: ["shani-event"]
                                        Drag.hotSpot.x: width / 2
                                        Drag.hotSpot.y: height / 2
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.summary + " · " + Tr.t("All day") + " — " + Tr.t("drag to another day")
                                        Rectangle {
                                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: 1; topMargin: 1; bottomMargin: 1 }
                                            width: Theme.px(3)
                                            color: parent.calColor
                                            radius: Theme.px(2)
                                        }
                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.px(6); anchors.rightMargin: Theme.px(4)
                                            text: modelData.summary
                                            color: Theme.text
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                            font.family: Theme.font
                                            font.pixelSize: Theme.type("caption")
                                        }
                                        MouseArea {
                                            id: chipDrag
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            drag.target: parent
                                            drag.threshold: Theme.px(8)
                                            onClicked: win.viewEvent(modelData)
                                            onReleased: { if (parent) { parent.x = 0; parent.y = 0; } }
                                        }
                                        KeyFocus { onActivated: win.viewEvent(modelData) }
                                    }
                                }
                            }
                        }
                    }
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(200)
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
                                id: hourRow
                                required property int index
                                readonly property int hour: index
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.preferredWidth: win.compact ? Theme.px(30) : Theme.px(44)
                                    Layout.maximumWidth: win.compact ? Theme.px(30) : Theme.px(44)
                                    Layout.fillWidth: false
                                    text: (hour < 10 ? "0" : "") + hour + ":00"
                                    color: Theme.faint
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: Theme.font
                                    font.pixelSize: Theme.type("caption")
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Repeater {
                                    model: 7
                                    Rectangle {
                                        id: hourCell
                                        required property int index
                                        readonly property var _evs: win.weekEventsForHour(index, hourRow.hour)
                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(Theme.touchTarget, _evs.length * Math.max(Theme.touchTarget, Theme.px(14)) + 2)
                                        radius: Theme.px(4)
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.stroke
                                        // drop on a day/hour cell to reschedule
                                        DropArea {
                                            anchors.fill: parent
                                            keys: ["shani-event"]
                                            onDropped: {
                                                const e = drag.source && drag.source.dragEvent;
                                                if (e) win.moveEventTo(e, win.weekDays[hourCell.index], hourRow.hour, false);
                                                drop.acceptProposedAction();
                                            }
                                        }
                                        Rectangle {
                                            visible: win.view === "week" && win.isNowHour(hourRow.hour)
                                            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: parent.height * win.nowFraction() }
                                            height: 2
                                            color: Theme.red
                                            z: 4
                                        }
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            spacing: 1
                                            Repeater {
                                                model: hourCell._evs.slice(0, 2)
                                                Rectangle {
                                                    required property var modelData
                                                    readonly property color calColor: win.eventColor(modelData.calendar)
                                                    Layout.fillWidth: true
                                                    implicitHeight: Math.max(Theme.touchTarget, Theme.px(14))
                                                    radius: Theme.px(3)
                                                    color: Theme.alpha(calColor, 0.45)
                                                    property var dragEvent: modelData
                                                    Drag.active: hourDrag.drag.active
                                                    Drag.keys: ["shani-event"]
                                                    Drag.hotSpot.x: width / 2
                                                    Drag.hotSpot.y: height / 2
                                                    Accessible.role: Accessible.Button
                                                    Accessible.name: modelData.summary + " " + win.zoneTime(modelData.start) + (modelData.calendar ? " · " + modelData.calendar : "") + " — " + Tr.t("drag to another day or hour")
                                                    Rectangle {
                                                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: 1; topMargin: 1; bottomMargin: 1 }
                                                        width: Theme.px(3)
                                                        color: parent.calColor
                                                        radius: Theme.px(2)
                                                    }
                                                    Text {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: Theme.px(6); anchors.rightMargin: Theme.px(3)
                                                        text: modelData.summary
                                                        color: Theme.text
                                                        elide: Text.ElideRight
                                                        verticalAlignment: Text.AlignVCenter
                                                        font.family: Theme.font
                                                        font.pixelSize: Theme.type("caption")
                                                    }
                                                    MouseArea {
                                                        id: hourDrag
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        drag.target: parent
                                                        drag.threshold: Theme.px(8)
                                                        onClicked: win.viewEvent(modelData)
                                                        onReleased: { if (parent) { parent.x = 0; parent.y = 0; } }
                                                    }
                                                    KeyFocus { onActivated: win.viewEvent(modelData) }
                                                }
                                            }
                                            Text {
                                                visible: hourCell._evs.length > 2
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Math.max(Theme.touchTarget, 14)
                                                verticalAlignment: Text.AlignVCenter
                                                text: Tr.t("+%1 more").arg(hourCell._evs.length - 2)
                                                color: Theme.accent
                                                font.family: Theme.font
                                                font.pixelSize: Theme.type("caption")
                                                Accessible.role: Accessible.Button
                                                Accessible.name: text
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: win.openDayFromWeek(hourCell.index)
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
                    font.pixelSize: Theme.type("small")
                }
            }

            // ---- day timetable: 00:00–23:00, events in their start hour ----
            Flickable {
                visible: win.view === "day"
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(220)
                contentHeight: dayHourCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: dayHourCol
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
                                Layout.preferredWidth: win.compact ? Theme.px(30) : Theme.px(44)
                                Layout.maximumWidth: win.compact ? Theme.px(30) : Theme.px(44)
                                Layout.fillWidth: false
                                text: (hour < 10 ? "0" : "") + hour + ":00"
                                color: Theme.faint
                                horizontalAlignment: Text.AlignHCenter
                                font.family: Theme.font
                                font.pixelSize: Theme.type("caption")
                                verticalAlignment: Text.AlignVCenter
                            }
                            Rectangle {
                                id: dayHourCell
                                readonly property var _evs: win.dayEventsForHour(hour)
                                Layout.fillWidth: true
                                implicitHeight: Math.max(Theme.touchTarget, _evs.length * Math.max(Theme.touchTarget, Theme.px(16)) + 2)
                                radius: Theme.px(4)
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.stroke
                                Rectangle {
                                    visible: win.view === "day" && win.isNowHour(hour)
                                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: parent.height * win.nowFraction() }
                                    height: 2
                                    color: Theme.red
                                    z: 4
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    spacing: 1
                                    Repeater {
                                        model: dayHourCell._evs
                                        Rectangle {
                                            required property var modelData
                                            readonly property color calColor: win.eventColor(modelData.calendar)
                                            Layout.fillWidth: true
                                            implicitHeight: Math.max(Theme.touchTarget, Theme.px(16))
                                            radius: Theme.px(3)
                                            color: Theme.alpha(calColor, 0.45)
                                            Accessible.role: Accessible.Button
                                            Accessible.name: modelData.summary + " " + win.zoneTime(modelData.start)
                                            Rectangle {
                                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: 1; topMargin: 1; bottomMargin: 1 }
                                                width: Theme.px(3)
                                                color: parent.calColor
                                                radius: Theme.px(2)
                                            }
                                            Text {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.px(6); anchors.rightMargin: Theme.px(4)
                                                text: win.zoneTime(modelData.start) + "  " + modelData.summary
                                                color: Theme.text
                                                elide: Text.ElideRight
                                                verticalAlignment: Text.AlignVCenter
                                                font.family: Theme.font
                                                font.pixelSize: Theme.type("caption")
                                            }
                                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.viewEvent(modelData) }
                                            KeyFocus { onActivated: win.viewEvent(modelData) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- year: 12 mini months; click a day for that day's view -----
            GridLayout {
                visible: win.view === "year"
                Layout.fillWidth: true
                columns: 3
                rowSpacing: Theme.px(8)
                columnSpacing: Theme.px(8)
                Repeater {
                    model: 12
                    Rectangle {
                        required property int index
                        readonly property int yy: win.month.getFullYear()
                        readonly property int mm: index
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(118)
                        radius: Theme.px(8)
                        color: Theme.alpha(Theme.stroke, 0.12)
                        border.width: 1
                        border.color: Theme.stroke
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(4)
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: Qt.formatDate(new Date(yy, mm, 1), "MMMM")
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.type("small")
                                font.weight: Font.DemiBold
                            }
                            Row {
                                Layout.fillWidth: true
                                property real cellW: width / 7
                                Repeater {
                                    model: win.weekNames
                                    Text {
                                        width: parent.cellW
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(8) * Theme.fontScale
                                    }
                                }
                            }
                            Grid {
                                id: yearGrid
                                Layout.fillWidth: true
                                columns: 7
                                readonly property real cell: width / 7
                                Repeater {
                                    model: win.yearMonthDays(yy, mm)
                                    Rectangle {
                                        required property int modelData
                                        readonly property bool todayCell: modelData > 0 && yy === win.today.getFullYear() && mm === win.today.getMonth() && modelData === win.today.getDate()
                                        width: yearGrid.cell
                                        height: Theme.px(14)
                                        color: "transparent"
                                        radius: Theme.px(3)
                                        Text {
                                            anchors.centerIn: parent
                                            visible: parent.modelData > 0
                                            text: parent.modelData
                                            color: parent.todayCell ? Theme.accent : Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: Theme.type("caption")
                                            font.weight: parent.todayCell ? Font.DemiBold : Font.Normal
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: parent.modelData > 0
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.selectYearDay(yy, mm, parent.modelData)
                                        }
                                        KeyFocus {
                                            enabled: parent.modelData > 0
                                            onActivated: win.selectYearDay(yy, mm, parent.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- agenda: upcoming and "earlier" (overdue) events -------------
            ColumnLayout {
                visible: win.view === "agenda"
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Upcoming (%1)").arg(win.agendaUpcoming.length)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: win.agendaUpcoming.slice(0, 20)
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: "x-office-calendar"
                        title: modelData.summary
                        subtitle: Agenda.when(modelData) + (modelData.location ? " · " + modelData.location : "") + (modelData.calendar ? " · " + modelData.calendar : "") + (modelData.allDay ? " · " + Tr.t("All day") : "")
                        onClicked: { win.showDayOf(modelData); win.viewEvent(modelData); }
                    }
                }
                EmptyState {
                    visible: win.agendaUpcoming.length === 0
                    icon: "x-office-calendar"
                    title: Tr.t("Nothing upcoming")
                    subtitle: Agenda.available ? Tr.t("New events appear here") : Tr.t("Add a calendar in Settings > Your account")
                }
                Choice {
                    Layout.fillWidth: true
                    text: win.showEarlier ? Tr.t("Hide earlier") : Tr.t("Show earlier (%1)").arg(win.agendaEarlier.length)
                    selected: win.showEarlier
                    Accessible.name: text
                    onClicked: win.showEarlier = !win.showEarlier
                }
                Repeater {
                    visible: win.showEarlier
                    model: win.agendaEarlier
                    ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        icon: "x-office-calendar"
                        title: modelData.summary
                        subtitle: Tr.t("Ended") + " " + Agenda.when(modelData) + (modelData.calendar ? " · " + modelData.calendar : "") + (modelData.allDay ? " · " + Tr.t("All day") : "")
                        onClicked: { win.showDayOf(modelData); win.viewEvent(modelData); }
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
                    font.pixelSize: Theme.type("body")
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: win.view === "month" && win.monthEvents.length > 0
                    text: Tr.t("%1 in this month").arg(win.monthEvents.length)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                Text {
                    visible: win.view === "week" && win.weekEvents.length > 0
                    text: Tr.t("%1 in this week").arg(win.weekEvents.length)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
            }

            // ---- which calendars show: a chip each, its colour beside its name ----
            Flow {
                Layout.fillWidth: true
                visible: !win.editor && Agenda.calendarNames.length > 1
                spacing: Theme.px(6)
                Repeater {
                    model: Agenda.calendarNames
                    Choice {
                        id: calChip
                        required property string modelData
                        text: (Agenda.colorOf(modelData) !== "" ? "● " : "") + modelData
                        selected: Agenda.isShown(modelData)
                        Accessible.name: modelData + ", " + (selected ? Tr.t("shown") : Tr.t("hidden"))
                        onClicked: Agenda.setShown(modelData, !Agenda.isShown(modelData))
                    }
                }
            }
            // ---- online accounts: a CalDAV server's calendars (GNOME Calendar's "Add calendar") ----
            RowLayout {
                visible: !win.editor
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Online accounts")
                    color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption")
                    Component.onCompleted: Agenda.loadAccounts()
                }
                IconButton { icon: "view-refresh"; size: Theme.px(22); tip: Tr.t("Read the accounts again"); onClicked: Agenda.loadAccounts() }
            }
            Repeater {
                model: win.editor ? [] : Agenda.accounts
                RowLayout {
                    id: accRow
                    required property var modelData
                    Layout.fillWidth: true
                    property bool confirm: false
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: accRow.modelData.name + (accRow.modelData.calendars.length ? "  ·  " + accRow.modelData.calendars.join(", ") : "  ·  " + Tr.t("finding its calendars…"))
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body")
                    }
                    IconButton {
                        icon: accRow.confirm ? "edit-delete" : "window-close"
                        size: Theme.px(22)
                        tip: accRow.confirm ? Tr.t("Click again: %1 is removed from this computer (nothing on the server changes)", accRow.modelData.name) : Tr.t("Remove %1", accRow.modelData.name)
                        onClicked: { if (accRow.confirm) Agenda.removeAccount(accRow.modelData.uid); accRow.confirm = !accRow.confirm; }
                    }
                }
            }
            Choice { visible: !win.editor; text: win.addingAccount ? Tr.t("Cancel") : Tr.t("Add an online calendar…"); onClicked: win.addingAccount = !win.addingAccount }
            ColumnLayout {
                visible: !win.editor && win.addingAccount
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        // where each provider keeps its CalDAV (the user name goes in by itself)
                        model: [["nextcloud", "Nextcloud", "https://YOUR-SERVER/remote.php/dav"], ["fastmail", "Fastmail", "https://caldav.fastmail.com/"],
                                ["icloud", "iCloud", "https://caldav.icloud.com/"], ["mailbox", "mailbox.org", "https://dav.mailbox.org/"],
                                ["other", Tr.t("Other CalDAV"), "https://"]]
                        Choice {
                            required property var modelData
                            text: modelData[1]
                            selected: win.accountKind === modelData[0]
                            onClicked: { win.accountKind = modelData[0]; accUrl.text = modelData[2]; accName.text = modelData[0] === "other" ? "" : modelData[1]; }
                        }
                    }
                }
                TextField { id: accName; Layout.fillWidth: true; placeholderText: Tr.t("Name, e.g. Work") }
                TextField { id: accUrl; Layout.fillWidth: true; placeholderText: "https://…" }
                TextField { id: accUser; Layout.fillWidth: true; placeholderText: Tr.t("User name") }
                TextField { id: accPass; Layout.fillWidth: true; secret: true; placeholderText: win.accountKind === "icloud" ? Tr.t("An app password (appleid.apple.com)") : Tr.t("Password (an app password, where it has them)") }
                Text {
                    visible: Agenda.accountError !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Agenda.accountError
                    color: Theme.danger; font.family: Theme.font; font.pixelSize: Theme.type("small")
                }
                Button {
                    kind: "primary"
                    busy: Agenda.accountBusy
                    text: Tr.t("Add")
                    enabled: !Agenda.accountBusy && /^https?:\/\/[^\s\/]+/.test(accUrl.text.trim()) && accUrl.text.indexOf("YOUR-SERVER") < 0 && accUser.text.trim() !== "" && accPass.text !== ""
                    onClicked: Agenda.addAccount(accName.text.trim(), accUrl.text.trim(), accUser.text.trim(), accPass.text)
                }
                Connections { target: Agenda; function onAccountBusyChanged() { if (!Agenda.accountBusy && Agenda.accountError === "") { win.addingAccount = false; accPass.text = ""; } } }
            }
            TextField {
                id: dateField
                visible: !win.editor && win.pickingDate
                Layout.fillWidth: true
                placeholder: Tr.t("Jump to date (yyyy-MM-dd)")
                label: Tr.t("Jump to date (yyyy-MM-dd)")
                error: text !== "" && !/^\d{4}-\d{2}-\d{2}$/.test(text.trim()) ? Tr.t("Use yyyy-MM-dd") : ""
                onAccepted: { if (win.goToDate(text)) text = "" }
            }
            RowLayout {
                visible: !win.editor
                Layout.fillWidth: true
                spacing: Theme.px(6)
                SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Search title, place or notes")
                    label: Tr.t("Search title, place or notes")
                    onTextChanged: { if (text !== Agenda.search) Agenda.search = text; }
                }
            }
            Connections { target: Agenda; function onSearchChanged() { if (Agenda.search !== searchField.text) searchField.text = Agenda.search; } }

            Text {
                visible: !win.editor && win.searchActive
                Layout.fillWidth: true
                text: Tr.t("%1 matches across all calendars").arg(win.searchResults.length)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }

            // ---- the day's events, all-calendar matches, or the editor ------
            Flickable {
                visible: !win.editor
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(190, dayList.implicitHeight + 4)
                Layout.minimumHeight: Theme.px(24)
                contentHeight: dayList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: dayList
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: win.searchActive ? win.searchResults : win.shownEvents
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "x-office-calendar"
                            title: modelData.summary
                            subtitle: Agenda.when(modelData) + (modelData.location ? " · " + modelData.location : "") + (modelData.calendar ? " · " + modelData.calendar : "") + (modelData.allDay ? " · " + Tr.t("All day") : "")
                            onClicked: {
                                if (win.searchActive) win.showDayOf(modelData);
                                win.viewEvent(modelData)
                            }
                        }
                    }
                    EmptyState {
                        visible: (win.searchActive ? win.searchResults.length : win.shownEvents.length) === 0
                        icon: "x-office-calendar"
                        title: Agenda.search !== "" ? Tr.t("No matches") : Tr.t("Nothing that day")
                        subtitle: Agenda.search !== "" ? Tr.t("Try another search") : Agenda.loadError !== "" ? Agenda.loadError : Agenda.available ? Tr.t("No events for this day") : Tr.t("Add a calendar in Settings > Your account")
                        actionText: Agenda.available ? Tr.t("Refresh") : ""
                        onAction: Agenda.refresh()
                    }
                }
            }

            // ---- create / edit / delete form -------------------------------
            ColumnLayout {
                visible: win.editor
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text {
                    Layout.fillWidth: true
                    text: win.editingEvent ? Tr.t("Edit event") : Tr.t("New event")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    visible: win.readOnlyEvent
                    Layout.fillWidth: true
                    implicitHeight: bannerText.implicitHeight + Theme.px(10)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    border.width: 1
                    border.color: Theme.danger
                    Text {
                        id: bannerText
                        anchors { fill: parent; margins: Theme.px(5) }
                        wrapMode: Text.Wrap
                        text: "This calendar is read-only — this event cannot be changed here."
                        color: Theme.danger
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
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
                TextField {
                    id: fDescription
                    Layout.fillWidth: true
                    placeholder: "Description / notes"
                    label: "Description"
                    Accessible.name: Tr.t("Event description")
                }
                TextField {
                    id: fAttendees
                    Layout.fillWidth: true
                    placeholder: Tr.t("Invite by email, separated by commas")
                    label: Tr.t("Attendees")
                }
                Text {
                    Layout.fillWidth: true
                    visible: fAttendees.text.trim() !== ""
                    text: Tr.t("Guests get an invitation through your mail app or calendar server. They can accept, decline or reply maybe.")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.type("caption")
                    wrapMode: Text.Wrap
                }
                Text { text: Tr.t("Repeat"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: [["NONE", "None"], ["DAILY", "Daily"], ["WEEKLY", "Weekly"], ["MONTHLY", "Monthly"], ["YEARLY", "Yearly"]]
                        Choice {
                            required property var modelData
                            text: modelData[1]
                            selected: win.fRepeat === modelData[0]
                            onClicked: { win.fRepeat = modelData[0]; win.repeatTouched = true; }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    TextField {
                        Layout.preferredWidth: Theme.px(90)
                        placeholder: "2"
                        label: Tr.t("Repeat every N periods")
                        text: String(win.fRepeatInterval)
                        enabled: win.fRepeat !== "NONE"
                        input.validator: IntValidator { bottom: 1; top: 99 }
                        onTextChanged: { const n = parseInt(text, 10); win.fRepeatInterval = isNaN(n) || n < 1 ? 1 : n; win.repeatTouched = true; }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: win.fRepeat === "WEEKLY"
                        text: Tr.t("On") + " " + (win.fByDay === "" ? Tr.t("the event's day") : win.fByDay)
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    visible: win.fRepeat === "WEEKLY"
                    spacing: Theme.px(4)
                    Repeater {
                        model: win.repeatDays
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: win.fByDay.split(",").indexOf(modelData) >= 0
                            Accessible.name: Tr.t("Repeat on %1").arg(modelData)
                            onClicked: win.toggleRepeatDay(modelData)
                        }
                    }
                }
                Text {
                    visible: win.complexRule
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Tr.t("This event has a repeat rule the form cannot fully edit. Changing the controls replaces it.")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("caption")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    TextField {
                        Layout.preferredWidth: Theme.px(150)
                        placeholder: "End repeat yyyy-MM-dd"
                        label: "End repeat"
                        text: win.fRepeatUntil
                        enabled: win.fRepeat !== "NONE"
                        onTextChanged: { win.fRepeatUntil = text; win.repeatTouched = true; }
                    }
                    TextField {
                        Layout.preferredWidth: Theme.px(90)
                        placeholder: "minutes"
                        label: "Reminder (minutes before)"
                        text: String(win.fAlarm)
                        input.validator: IntValidator { bottom: 0; top: 1440 }
                        onTextChanged: { const n = parseInt(text, 10); win.fAlarm = isNaN(n) ? 0 : n; }
                    }
                }
                Text { text: Tr.t("Time zone"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: win.zones
                        Choice {
                            required property var modelData
                            text: modelData[1]
                            selected: win.fZone === modelData[0]
                            onClicked: win.fZone = modelData[0]
                        }
                    }
                }
                // the calendar this event belongs to: fixed when editing,
                // chosen (Agenda.selectedCalendar) when new
                Flow {
                    visible: !win.editingEvent
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Choice { text: Tr.t("The first one"); selected: Agenda.selectedCalendar === ""; onClicked: Agenda.selectedCalendar = "" }
                    Repeater {
                        model: Agenda.writableNames
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: Agenda.selectedCalendar === modelData
                            onClicked: Agenda.selectedCalendar = modelData
                        }
                    }
                }
                Text {
                    visible: win.editingEvent !== null && win.editingEvent.calendar !== undefined
                    Layout.fillWidth: true
                    text: Tr.t("Calendar: %1").arg(win.editingEvent ? win.editingEvent.calendar : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    TextField { id: fDateA; Layout.preferredWidth: Theme.px(110); placeholder: "2026-11-08"; label: Tr.t("Start date (yyyy-MM-dd)") }
                    TextField { id: fTimeA; Layout.preferredWidth: Theme.px(70); placeholder: "09:00"; label: Tr.t("Start time (HH:mm)"); enabled: !win.fAllDay }
                    Button {
                        text: win.fAllDay ? Tr.t("All-day: on") : Tr.t("All-day: off")
                        Accessible.name: Tr.t("Toggle all-day; the original time is kept")
                        kind: "outline"
                        onClicked: win.toggleAllDay()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    TextField { id: fDateB; Layout.preferredWidth: Theme.px(110); placeholder: "2026-11-08"; label: Tr.t("End date (yyyy-MM-dd)") }
                    TextField { id: fTimeB; Layout.preferredWidth: Theme.px(70); placeholder: "10:00"; label: Tr.t("End time (HH:mm)"); enabled: !win.fAllDay }
                }
                Text {
                    visible: win.formError !== ""
                    Layout.fillWidth: true
                    text: win.formError
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                Text {
                    visible: Agenda.writeError !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Agenda.writeError
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Button { Layout.fillWidth: true; text: Tr.t("Save"); kind: "primary"; enabled: !win.readOnlyEvent; onClicked: win.saveEditor() }
                    Button { Layout.fillWidth: true; text: Tr.t("Cancel"); onClicked: win.closeEditor() }
                    Button {
                        visible: win.editingEvent !== null
                        text: win.confirmDelete ? Tr.t("Confirm delete") : Tr.t("Delete")
                        kind: "danger"
                        enabled: !win.readOnlyEvent
                        onClicked: win.deleteEditor()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: win.editor ? Tr.t("Esc closes the form") : Tr.t("Esc closes · arrows move · Home today · PageUp/Down change period · drag an event to reschedule")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("small")
            }
        }

        // ---- click-to-view detail sheet (edit is a second, deliberate step) ----
        Rectangle {
            visible: win.viewing
            anchors.fill: parent
            z: 10
            color: Qt.rgba(0, 0, 0, 0.5)
            MouseArea { anchors.fill: parent; onClicked: { win.viewing = false; win.viewingEvent = null; } }
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.px(48), Theme.px(460))
                height: Math.min(detailCol.implicitHeight + Theme.px(48), parent.height - Theme.px(24))
                radius: Theme.radiusLarge
                color: Theme.surface1
                border.width: 1
                border.color: Theme.border
                Flickable {
                    anchors.fill: parent
                    anchors.margins: Theme.px(12)
                    contentWidth: width
                    contentHeight: detailCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: detailCol
                        width: parent.width
                        spacing: Theme.px(6)
                    Text {
                        Layout.fillWidth: true
                        text: (win.viewingEvent || {}).summary || ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.type("heading")
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.detailWhen(win.viewingEvent)
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("body")
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!((win.viewingEvent || {}).location)
                        text: (win.viewingEvent || {}).location || ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!((win.viewingEvent || {}).calendar)
                        text: Tr.t("Calendar: %1").arg((win.viewingEvent || {}).calendar || "")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
                    Rectangle {
                        visible: win.readOnlyEvent
                        Layout.fillWidth: true
                        implicitHeight: roText.implicitHeight + Theme.px(8)
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        border.width: 1
                        border.color: Theme.danger
                        Text {
                            id: roText
                            anchors { fill: parent; margins: Theme.px(4) }
                            wrapMode: Text.Wrap
                            text: "This calendar is read-only."
                            color: Theme.danger
                            font.family: Theme.font
                            font.pixelSize: Theme.type("small")
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!((win.viewingEvent || {}).description)
                        text: (win.viewingEvent || {}).description || ""
                        Accessible.name: Tr.t("Description: %1", text)
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.type("body")
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(8)
                        Button { Layout.fillWidth: true; text: Tr.t("Close"); onClicked: { win.viewing = false; win.viewingEvent = null; } }
                        Button {
                            Layout.fillWidth: true
                            text: Tr.t("Add note")
                            Accessible.name: Tr.t("Add a note for this event")
                            onClicked: win.noteForEvent(win.viewingEvent)
                        }
                        Button { Layout.fillWidth: true; text: Tr.t("Edit"); kind: "primary"; onClicked: win.editViewed() }
                    }
                    }
                }
            }
        }
    }

    // Escape unwinds the sheet first, then closes through the guard; Ctrl+R is
    // AppWindow's refresh (shortcutRefresh above), so no local Shortcut for it.
    Shortcut { sequence: "Escape"; onActivated: { if (win.viewing) { win.viewing = false; win.viewingEvent = null; } else if (win.editor) win.closeEditor(); else win.requestClose(); } }
}
