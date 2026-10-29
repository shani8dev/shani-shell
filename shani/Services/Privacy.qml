pragma Singleton
// Camera: in-use detection (any process of ours holding /dev/video*) and the
// kill switch — unloading uvcvideo, authorised through the polkit agent.
// Event-driven (bridge/devwatch.py): nothing runs while no camera is touched.
// Microphone in-use comes from PipeWire (Audio.micInUse).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool cameraPresent: false
    property bool cameraEnabled: true
    property bool cameraInUse: false
    readonly property bool micInUse: Audio.micInUse

    function toggleCamera() {
        Quickshell.execDetached(["pkexec", "modprobe", cameraEnabled ? "-r" : "", "uvcvideo"].filter(a => a !== ""));
        recheck.restart();
    }

    Timer { id: recheck; interval: 1500; onTriggered: state.running = true }
    // a camera plugged in or out (Services/Camera lists them again)
    signal camerasChanged()
    // bridge/devwatch.py: inotify on /dev - a camera appearing, opened, closed.
    // The look at who holds it (state) runs on those events only; it used to
    // scan every process's open files every 3 s.
    Timer { id: settle; interval: 250; onTriggered: state.running = true }
    Process {
        id: watcher
        running: true
        command: ["python3", Quickshell.env("SHANI_DEVWATCH_TOOL") || "/usr/lib/shani-shell/devwatch.py"]
        stdout: SplitParser {
            onRead: line => {
                if (line === "devices") root.camerasChanged();
                settle.restart();
            }
        }
        // ends only if inotify could not start: then a slow look, as before
        onExited: fallback.running = true
    }
    Timer { id: fallback; interval: 10000; repeat: true; triggeredOnStart: true; onTriggered: state.running = true }
    Process {
        id: state
        command: ["sh", "-c", "test -d /sys/module/uvcvideo && echo loaded; ls /sys/class/video4linux 2>/dev/null | head -1; find /proc/[0-9]*/fd -lname '/dev/video*' -print -quit 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l !== "");
                root.cameraEnabled = lines.indexOf("loaded") >= 0;
                root.cameraPresent = root.cameraEnabled || lines.some(l => l.startsWith("video"));
                root.cameraInUse = lines.some(l => l.startsWith("/proc/"));
            }
        }
    }
}
