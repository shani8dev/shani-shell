pragma Singleton
// Other cities' clocks on the control centre's calendar (Settings > Date &
// language picks the zones). Read where the kernel keeps them — /usr/share/
// zoneinfo via `date`, so DST just works — and refreshed every 30 s only while
// any city is chosen; none chosen, nothing runs.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var clocks: []   // [{ zone, city, time }]

    Process {
        id: read
        // "$@" is the zones; the leading "" is $0 (a shell -c argument, not a zone)
        command: ["sh", "-c", 'for z in "$@"; do echo "$z / $(TZ=$z date "+%a %H:%M")"; done', ""].concat(Array.from(Settings.data.worldClocks || []))
        stdout: StdioCollector {
            onStreamFinished: {
                root.clocks = text.trim().split("\n").filter(l => l).map(l => {
                    const z = l.split(" / ")[0];
                    return { zone: z, city: z.split("/").pop().replace(/_/g, " "), time: l.split(" / ")[1] || "" };
                });
            }
        }
    }
    Timer {
        interval: 30000
        running: Settings.loaded && Settings.data.worldClocks.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: read.running = Settings.data.worldClocks.length > 0
    }
    // settings load after us (or the person picks a city now)
    Connections {
        target: Settings
        function onLoadedChanged() { root.refresh(); }
    }
    Connections {
        target: Settings.data
        function onWorldClocksChanged() { root.refresh(); }
    }
    function refresh() {
        if (Settings.loaded && Settings.data.worldClocks.length > 0)
            read.running = true;
    }
}
