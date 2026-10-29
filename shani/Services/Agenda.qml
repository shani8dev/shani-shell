pragma Singleton
// The coming week from the person's calendars (Evolution Data Server, through
// bridge/agenda.py): shown under the sidebar's calendar, and a heads-up ten
// minutes before each timed event, once. "Open" is GNOME Calendar (a Flatpak
// in the image), which writes to the same calendars.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_AGENDA_TOOL") || "/usr/lib/shani-shell/agenda.py"
    property var events: []               // [{ start, end, summary, location, calendar, allDay }] (seconds)
    property bool available: false
    property var told: ({})
    // what is still to come, today first
    readonly property var upcoming: events.filter(e => e.end * 1000 > Date.now()).slice(0, 6)

    function refresh() { if (!read.running) read.running = true; }
    function openCalendar() {
        Quickshell.execDetached(["sh", "-c", "command -v gnome-calendar >/dev/null && exec gnome-calendar; exec flatpak run org.gnome.Calendar"]);
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
                try { root.events = JSON.parse(text); root.available = true; } catch (e) {}
            }
        }
        onExited: code => { if (code === 2) root.available = false; }
    }
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
