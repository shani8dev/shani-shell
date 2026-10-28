pragma Singleton
// A focus timer (pomodoro): 25 minutes of Work focus — notifications held
// back — then a nudge to rest. Any length can be chosen; stopping early ends
// the focus mode it started (and only that one).
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    property int total: 0                // seconds
    property int left: 0
    readonly property bool running: left > 0
    readonly property string label: Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0")
    property bool startedFocus: false

    function start(minutes) {
        total = minutes * 60;
        left = total;
        // take Work focus unless another mode is already on
        startedFocus = Settings.data.focusMode === "";
        if (startedFocus)
            Settings.data.focusMode = "Work";
    }
    function stop() {
        left = 0;
        if (startedFocus && Settings.data.focusMode === "Work")
            Settings.data.focusMode = "";
        startedFocus = false;
    }

    Timer {
        interval: 1000
        running: root.running
        repeat: true
        onTriggered: {
            root.left -= 1;
            if (root.left <= 0) {
                root.stop();
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Focus timer", "-i", "alarm-symbolic",
                    "Time for a break", Math.round(root.total / 60) + " minutes of focus done"]);
            }
        }
    }
}
