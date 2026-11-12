pragma Singleton
// The coming week from the person's calendars (Evolution Data Server, through
// bridge/agenda.py): shown under the sidebar's calendar, and a heads-up ten
// minutes before each timed event, once. openCalendar() opens THIS shell's
// Calendar surface (Modules/Calendar/CalendarPanel.qml) — never GNOME
// Calendar; the shell surface writes to the same EDS calendars.
//
// Writes (addEvent/editEvent/deleteEvent) go to bridge/agenda.py add|edit|
// delete, which writes over EDS. When the script reports no calendar service
// (exit 2 — no EDS bindings or registry, e.g. in a minimal container), the
// change falls back to Chronoa's calendar_edit skill via a Bridge "ask" in
// words; the event list refreshes afterwards either way.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_AGENDA_TOOL") || "/usr/lib/shani-shell/agenda.py"
    property var allEvents: []            // [{ start, end, summary, location, calendar, allDay, uid }] (seconds)
    // what everything shows: the events of the calendars not hidden
    readonly property var events: hidden.length ? allEvents.filter(e => hidden.indexOf(e.calendar) < 0) : allEvents
    property bool available: false
    property string search: ""            // title filter for the Calendar surface
    // the calendars there are ([{ name, uid, color, readOnly }], agenda.py
    // calendars), the ones the person chose not to see (by name, kept in
    // Settings) and the one a new event goes to ("" = the first one)
    property var calendars: []
    readonly property var calendarNames: calendars.length ? calendars.map(c => c.name) : [...new Set(allEvents.map(e => e.calendar).filter(n => n))].sort()
    readonly property var writableNames: calendars.length ? calendars.filter(c => !c.readOnly).map(c => c.name) : calendarNames
    readonly property var hidden: Array.from(Settings.data.calendarsHidden || [])
    function isShown(name) { return hidden.indexOf(name) < 0; }
    function setShown(name, on) {
        const list = hidden.filter(n => n !== name);
        if (!on)
            list.push(name);
        Settings.data.calendarsHidden = list;
    }
    function colorOf(name) { const c = calendars.find(x => x.name === name); return c && c.color ? c.color : ""; }
    property string selectedCalendar: ""
    property var told: ({})
    // what is still to come, today first
    readonly property var upcoming: events.filter(e => e.end * 1000 > Date.now()).slice(0, 6)

    function refresh() { if (!read.running) read.running = true; if (!sources.running) sources.running = true; }
    Process {
        id: sources
        command: ["python3", root.tool, "calendars"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.calendars = JSON.parse(text); } catch (e) {} }
        }
    }
    // the shell's own Calendar surface (the editor lives there), never
    // GNOME Calendar
    function openCalendar() {
        Ui.closeAll();
        Ui.calendar = true;
    }

    // ---- writes ------------------------------------------------------------
    // payload: { summary, start (sec), end (sec), location, allDay }
    function addEvent(payload) { _write("add", payload, "Add a calendar event"); }
    function editEvent(payload) { _write("edit", payload, "Edit the calendar event"); }
    function deleteEvent(payload) { _write("delete", payload, "Delete the calendar event"); }

    function _write(action, payload, verb) {
        const p = {
            summary: String(payload.summary || "").trim(),
            start: Number(payload.start || 0),
            end: Number(payload.end || 0),
            location: String(payload.location || ""),
            allDay: !!payload.allDay,
            calendar: payload.calendar || "",
            uid: payload.uid || ""
        };
        // delete/edit by uid only: fill the rest from the last read
        if (p.uid !== "" && (p.start === 0 || p.summary === "")) {
            const found = root.events.find(e => e.uid === p.uid);
            if (found) {
                if (p.start === 0) p.start = found.start;
                if (p.end === 0) p.end = found.end;
                if (p.summary === "") p.summary = found.summary;
                if (p.location === "") p.location = found.location || "";
                if (p.calendar === "") p.calendar = found.calendar || "";
                p.allDay = !!found.allDay;
            }
        }
        const when = new Date(p.start * 1000);
        const endWhen = new Date(p.end * 1000);
        writeProc.fallback = verb + " titled \"" + (p.summary || "(no title)") + "\" on " + Qt.formatDate(when, "yyyy-MM-dd") + " at " + Qt.formatTime(when, "HH:mm") + " to " + Qt.formatTime(endWhen, "HH:mm") + (p.allDay ? " (all day)" : "") + (p.location ? " at " + p.location : "");
        writeProc.command = ["python3", root.tool, action, JSON.stringify(p)];
        if (!writeProc.running)
            writeProc.running = true;
    }

    function when(e) {
        const s = new Date(e.start * 1000), now = new Date();
        const day = s.toDateString() === now.toDateString() ? "Today"
            : s.toDateString() === new Date(now.getTime() + 86400000).toDateString() ? "Tomorrow" : Qt.formatDate(s, "ddd d MMM");
        return day + (e.allDay ? "" : " · " + Qt.formatTime(s, "HH:mm"));
    }

    Process {
        id: read
        command: ["python3", root.tool, "7"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.allEvents = JSON.parse(text); root.available = true; } catch (e) {}
            }
        }
        onExited: code => { if (code === 2) root.available = false; }
    }
    Process {
        id: writeProc
        property string fallback: ""
        // exit 0: done over EDS. Anything else: no calendar service here, so
        // ask Chronoa's calendar_edit skill in words and refresh either way.
        onExited: code => {
            if (code !== 0 && fallback !== "") {
                if (!Bridge.send({ op: "ask", text: fallback }))
                    Quickshell.execDetached(["notify-send", "-a", "Calendar", "-i", "x-office-calendar", "No calendar service",
                        "EDS is unavailable and Chronoa is not connected; the change was not saved."]);
                else
                    quclock.restart();
            }
            root.refresh();
        }
    }
    // give Chronoa a moment to record the change before we re-read EDS
    Timer { id: quclock; interval: 1500; onTriggered: root.refresh() }
    Timer { interval: 10 * 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    // ten minutes before: once per event start
    Timer {
        interval: 30000
        running: root.events.length > 0
        repeat: true
        onTriggered: {
            const now = Date.now() / 1000;
            for (const e of root.events) {
                const key = e.summary + "@" + e.start;
                if (!e.allDay && e.start - now <= 600 && e.start - now > 0 && !root.told[key]) {
                    root.told[key] = true;
                    Quickshell.execDetached(["notify-send", "-a", "Calendar", "-i", "x-office-calendar",
                        e.summary + " in " + Math.max(1, Math.round((e.start - now) / 60)) + " min",
                        Qt.formatTime(new Date(e.start * 1000), "HH:mm") + (e.location ? " · " + e.location : "")]);
                }
            }
        }
    }
}
