pragma Singleton
// Dark/light preference for apps: org.gnome.desktop.interface color-scheme,
// which xdg-desktop-portal-gnome serves to GTK, Qt (6.5+), Electron and browsers.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    readonly property bool dark: Settings.data.darkMode

    function toggle() {
        Settings.data.darkMode = !Settings.data.darkMode;
    }

    Process {
        running: true
        command: ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", Settings.data.darkMode ? "prefer-dark" : "default"]
        onCommandChanged: running = true
    }
}
