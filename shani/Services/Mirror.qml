pragma Singleton
// An Android phone's screen in a window (Windows' Phone Link, macOS's iPhone
// Mirroring) with scrcpy: the screen, its sound, and the mouse and keyboard
// driving it. Phones are the ones adb sees - by USB with USB debugging on, or
// already on Wi-Fi (`adb connect`); "Over Wi-Fi" moves a USB one to Wi-Fi
// (scrcpy --tcpip), so the cable can come out.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string scrcpy: Quickshell.env("SHANI_SCRCPY") || "scrcpy"
    readonly property string adb: Quickshell.env("SHANI_ADB") || "adb"
    property bool available: false
    property var devices: []             // [{ serial, name, wifi }]
    property string last: ""             // the serial mirrored last (the tests)

    function refresh() { if (available && !list.running) list.running = true; }
    function mirror(serial, wifi) {
        const d = devices.find(x => x.serial === serial);
        last = serial;
        Quickshell.execDetached([root.scrcpy, "-s", serial, "--window-title", d ? d.name : serial, "--stay-awake"]
            .concat(wifi ? ["--tcpip"] : []));
    }

    Process {
        running: true
        command: ["sh", "-c", 'command -v "$0" >/dev/null && command -v "$1" >/dev/null', root.scrcpy, root.adb]
        onExited: code => { root.available = code === 0; root.refresh(); }
    }
    // `adb devices -l`: "SERIAL  device usb:1-2 product:x model:Pixel_7 device:y"
    Process {
        id: list
        command: [root.adb, "devices", "-l"]
        stdout: StdioCollector {
            onStreamFinished: root.devices = text.split("\n").slice(1).map(l => l.trim().split(/\s+/))
                .filter(f => f.length >= 2 && f[1] === "device").map(f => {
                    const m = f.find(x => x.startsWith("model:"));
                    return { serial: f[0], name: m ? m.slice(6).replace(/_/g, " ") : f[0], wifi: /:\d+$/.test(f[0]) };
                })
        }
    }
}
