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
    id: root
    readonly property bool dark: Settings.data.darkMode

    function toggle() {
        Settings.data.darkMode = !Settings.data.darkMode;
    }

    readonly property var d: Settings.data
    // the icon theme the shell started with (it cannot change it while running)
    readonly property string shellIconTheme: Quickshell.env("QS_ICON_THEME") || "Adwaita"
    // Papirus comes in a light and a dark variant: the one for the style in use
    readonly property string iconThemeNow: d.iconTheme === "Papirus" ? (dark ? "Papirus-Dark" : "Papirus-Light") : d.iconTheme
    readonly property bool iconsNeedRestart: Settings.loaded && iconThemeNow !== shellIconTheme
    function restartShell() { Quickshell.execDetached(["systemctl", "--user", "restart", "shani-shell.service"]); }

    // ---- automatic dark style: switches at the boundaries only, so a hand
    // change holds until the next one ----------------------------------------
    property var lastWanted: null
    // sunrise and sunset in minutes since local midnight, for the weather
    // location (a solar approximation, within minutes); 7 pm – 7 am without one
    function sunTimes() {
        const lat = d.weatherLat, lon = d.weatherLon;
        if (!lat && !lon)
            return [7 * 60, 19 * 60];
        const now = new Date(), start = new Date(now.getFullYear(), 0, 0);
        const n = Math.floor((now - start) / 86400000);
        const rad = Math.PI / 180;
        const decl = 23.44 * Math.sin(rad * 360 / 365 * (n - 81));
        const cosH = (Math.sin(-0.833 * rad) - Math.sin(lat * rad) * Math.sin(decl * rad)) / (Math.cos(lat * rad) * Math.cos(decl * rad));
        if (cosH <= -1) return [0, 24 * 60];          // midnight sun
        if (cosH >= 1) return [12 * 60, 12 * 60];     // polar night
        const h = Math.acos(cosH) / rad / 15;         // half the day, in hours
        const noonUtc = 12 - lon / 15;
        const tz = -now.getTimezoneOffset() / 60;
        return [Math.round((noonUtc - h + tz) * 60), Math.round((noonUtc + h + tz) * 60)].map(m => (m % 1440 + 1440) % 1440);
    }
    function minutes(s) { const m = /^(\d\d?):(\d\d)$/.exec(s || ""); return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : -1; }
    function wantDark() {
        const now = new Date(), t = now.getHours() * 60 + now.getMinutes();
        let from, to;
        if (d.darkSchedule === "sunset") {
            const s = sunTimes();
            from = s[1]; to = s[0];
        } else {
            from = minutes(d.darkFrom); to = minutes(d.darkTo);
        }
        return from < to ? t >= from && t < to : t >= from || t < to;
    }
    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: Settings.loaded && root.d.darkSchedule !== "manual"
        onTriggered: {
            const want = root.wantDark();
            if (want !== root.lastWanted)
                Settings.data.darkMode = want;
            root.lastWanted = want;
        }
        onRunningChanged: root.lastWanted = null
    }
    // ---- wallpaper slideshow: the pictures in a folder, one after another ----
    property int slide: 0
    Timer {
        interval: Math.max(1, root.d.slideshowMinutes) * 60000
        repeat: true
        triggeredOnStart: true
        running: Settings.loaded && root.d.slideshowDir !== ""
        onTriggered: slides.running = true
    }
    Process {
        id: slides
        command: ["sh", "-c", 'find "$1" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort', "sh",
                  root.d.slideshowDir.replace(/^~/, Quickshell.env("HOME"))]
        stdout: StdioCollector {
            onStreamFinished: {
                const pics = text.trim().split("\n").filter(x => x);
                if (!pics.length)
                    return;
                root.slide = (root.slide + 1) % pics.length;
                Settings.data.wallpaper = pics[root.slide];
                Settings.data.wallpaperLight = "";
                Settings.data.wallpaperDark = "";
            }
        }
    }

    // overlay scrollbars (GTK's) appear on use; off: always there
    Process {
        running: Settings.loaded
        command: ["gsettings", "set", "org.gnome.desktop.interface", "overlay-scrolling", String(!root.d.showScrollbars)]
        onCommandChanged: if (Settings.loaded) running = true
    }

    Process {
        running: true
        command: ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", Settings.data.darkMode ? "prefer-dark" : "default"]
        onCommandChanged: running = true
    }
    // once the settings are read, so a first start does not write defaults over the person's own
    Process {
        running: Settings.loaded
        // also: GTK 3 apps in adw-gtk3 (light or dark, so they match GTK 4 ones),
        // libadwaita's accent, the document font, and font rendering
        command: ["sh", "-c", 'k=org.gnome.desktop.interface
            gsettings set $k icon-theme "$1"; gsettings set $k cursor-theme "$2"; gsettings set $k cursor-size "$3"
            gsettings set $k font-name "$4"; gsettings set $k document-font-name "$4"; gsettings set $k monospace-font-name "$5"
            [ -d /usr/share/themes/adw-gtk3 ] && gsettings set $k gtk-theme "$6"
            gsettings set $k accent-color "$7" 2>/dev/null
            gsettings set $k font-hinting slight; gsettings set $k font-antialiasing grayscale; true', "sh",
            root.iconThemeNow, d.cursorTheme, String(d.cursorSize), d.uiFont + " " + d.uiFontSize, d.monoFont + " " + d.monoFontSize,
            d.darkMode ? "adw-gtk3-dark" : "adw-gtk3", d.accentName || "teal"]
        onCommandChanged: if (Settings.loaded) running = true
    }
}
