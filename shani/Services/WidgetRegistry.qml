pragma Singleton
// The desktop widgets' catalogue: what each one is, how big it starts, which
// existing service it reads and what it needs before it has anything to show.
// Metadata only - no data source, no poller, no window. The toggles live in
// SettingsPage, the cards in DesktopWidgets and MoreWidgets.
import Quickshell
import QtQuick

Singleton {
    id: root
    // label, desc and note are untranslated source strings: callers pass them
    // through Tr.t(). `need` drives isAvailable(); `service` is the singleton
    // the widget already reads (named here, never instantiated here).
    readonly property var catalog: [
        {
            id: "clock",
            label: "Clock",
            desc: "time, date and the next event",
            size: { w: 216, h: 90 },
            service: "SystemClock",
            need: "always",
            note: ""
        },
        {
            id: "media",
            label: "Now playing",
            desc: "art, title and a seek bar while something plays",
            size: { w: 252, h: 80 },
            service: "Media",
            need: "player",
            note: "needs a player"
        },
        {
            id: "weather",
            label: "Weather",
            desc: "the current weather for your city",
            size: { w: 196, h: 92 },
            service: "Weather",
            need: "net",
            note: "needs Net and a city"
        },
        {
            id: "stats",
            label: "System monitor",
            desc: "cpu and memory levels, the network's throughput",
            size: { w: 212, h: 156 },
            service: "SysStats",
            need: "always",
            note: ""
        },
        {
            id: "agenda",
            label: "Agenda",
            desc: "the next events from your calendar",
            size: { w: 260, h: 82 },
            service: "Agenda",
            need: "calendar",
            note: "needs a calendar"
        },
        {
            id: "battery",
            label: "Battery",
            desc: "the charge and time left",
            size: { w: 196, h: 92 },
            service: "Power",
            need: "battery",
            note: "needs a battery"
        },
        {
            id: "note",
            label: "Note",
            desc: "your quick note from the control centre",
            size: { w: 240, h: 90 },
            service: "QuickNotes",
            need: "always",
            note: ""
        },
        {
            id: "clocks",
            label: "World clocks",
            desc: "the cities you picked under the calendar",
            size: { w: 236, h: 70 },
            service: "WorldClock",
            need: "cities",
            note: "needs cities under the calendar"
        }
    ]

    function entry(id) { return catalog.find(x => x.id === id) || null; }
    function labelFor(id) { const e = entry(id); return e ? e.label : ""; }
    function descFor(id) { const e = entry(id); return e ? e.desc : ""; }
    function noteFor(id) { const e = entry(id); return e ? e.note : ""; }

    // Answers from the services the widgets already use; nothing is started
    // and nothing is polled to answer this.
    function isAvailable(id) {
        const e = entry(id);
        if (!e) return false;
        switch (e.need) {
        case "net": return Net.online && Weather.enabled;
        case "calendar": return Agenda.available;
        case "battery": return Power.hasBattery;
        case "cities": return WorldClock.clocks.length > 0;
        case "player": return Media.current !== null;
        default: return true;
        }
    }
}
