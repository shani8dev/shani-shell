pragma Singleton
// The wallpaper, kept in step with GNOME's setting for it
// (org.gnome.desktop.background picture-uri / picture-uri-dark): the
// desktop portal's Wallpaper ("Set as wallpaper" in an image viewer, a
// browser, a Flatpak) and many apps write that key, so the shell follows it;
// and a change in Settings is written there too, for the apps that read it.
// `gsettings monitor` is one long-running process that wakes only on a change.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    // what the key and the shell agree on, so neither direction echoes the other
    property string seenLight: ""
    property string seenDark: ""

    function path(uri) {
        const m = /^'?(file:\/\/)?([^']*)'?$/.exec(String(uri).trim());
        return m ? decodeURIComponent(m[2]) : "";
    }
    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.background"]
        stdout: SplitParser {
            onRead: line => {
                const m = /^(picture-uri(-dark)?):\s*(.*)$/.exec(line.trim());
                if (!m || !Settings.loaded)
                    return;
                const p = root.path(m[3]);
                if (!p || p.indexOf("/") !== 0)
                    return;
                if (m[2]) {
                    root.seenDark = p;
                    if (Settings.data.wallpaperDark !== p) Settings.data.wallpaperDark = p;
                } else {
                    root.seenLight = p;
                    if (Settings.data.wallpaperLight !== p) Settings.data.wallpaperLight = p;
                }
            }
        }
    }
    readonly property string light: Settings.loaded ? (Settings.data.wallpaperLight || Settings.data.wallpaper || "") : ""
    readonly property string dark: Settings.loaded ? (Settings.data.wallpaperDark || Settings.data.wallpaper || "") : ""
    onLightChanged: if (light && light !== seenLight) { seenLight = light; write("picture-uri", light); }
    onDarkChanged: if (dark && dark !== seenDark) { seenDark = dark; write("picture-uri-dark", dark); }
    function write(key, p) {
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.background", key, "file://" + p]);
    }
}
