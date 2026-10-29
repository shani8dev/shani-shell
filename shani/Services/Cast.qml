pragma Singleton
// Cast the screen to a TV or a Chromecast: GNOME Network Displays (Miracast and
// Chromecast), sharing through the desktop portal niri supports — the Flatpak
// the images ship (org.gnome.NetworkDisplays), or a native install.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool available: false
    function open() {
        Quickshell.execDetached(["sh", "-c", "command -v gnome-network-displays >/dev/null && exec gnome-network-displays; exec flatpak run org.gnome.NetworkDisplays"]);
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v gnome-network-displays || flatpak info org.gnome.NetworkDisplays >/dev/null 2>&1"]
        onExited: code => root.available = code === 0
    }
}
