pragma Singleton
// How apps look, through org.gnome.desktop.interface — which GTK reads, and
// xdg-desktop-portal-gnome serves to Qt (6.5+), Electron and browsers: the
// dark/light preference, the icon and cursor themes, the interface and
// monospace fonts. niri's own cursor is InputConfig's; the shell's icons follow
// the theme from its next start (shani-shell.service reads it).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    readonly property bool dark: Settings.data.darkMode

    function toggle() {
        Settings.data.darkMode = !Settings.data.darkMode;
    }

    readonly property var d: Settings.data
    // the icon theme the shell started with (it cannot change it while running)
    readonly property string shellIconTheme: Quickshell.env("QS_ICON_THEME") || "Adwaita"
    readonly property bool iconsNeedRestart: Settings.loaded && d.iconTheme !== shellIconTheme
    function restartShell() { Quickshell.execDetached(["systemctl", "--user", "restart", "shani-shell.service"]); }

    Process {
        running: true
        command: ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", Settings.data.darkMode ? "prefer-dark" : "default"]
        onCommandChanged: running = true
    }
    // once the settings are read, so a first start does not write defaults over the person's own
    Process {
        running: Settings.loaded
        command: ["sh", "-c", 'k=org.gnome.desktop.interface
            gsettings set $k icon-theme "$1"; gsettings set $k cursor-theme "$2"; gsettings set $k cursor-size "$3"
            gsettings set $k font-name "$4"; gsettings set $k monospace-font-name "$5"', "sh",
            d.iconTheme, d.cursorTheme, String(d.cursorSize), d.uiFont + " " + d.uiFontSize, d.monoFont + " " + d.monoFontSize]
        onCommandChanged: if (Settings.loaded) running = true
    }
}
