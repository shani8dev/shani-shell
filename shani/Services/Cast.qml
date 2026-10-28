pragma Singleton
// Cast the screen to a TV or a Chromecast: GNOME Network Displays (Miracast and
// Chromecast), sharing through the desktop portal niri supports.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool available: false
    function open() { Quickshell.execDetached(["gnome-network-displays"]); }
    Process {
        running: true
        command: ["sh", "-c", "command -v gnome-network-displays"]
        onExited: code => root.available = code === 0
    }
}
