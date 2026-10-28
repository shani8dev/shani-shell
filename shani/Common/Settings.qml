pragma Singleton
// User settings: ~/.config/shani-shell/settings.json, created on first change.
// Defaults live in the adapter below, so a missing or partial file is fine.
// The file is watched: editing it by hand applies without restarting the shell,
// and the shell's own toggles (DND, caffeine, …) write back through it.
// SHANI_SHELL_SETTINGS overrides the path (tests point it at a scratch file).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string path: Quickshell.env("SHANI_SHELL_SETTINGS")
        || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/shani-shell/settings.json")

    property alias data: adapter
    property bool loaded: false

    // Write after a burst of changes settles, not once per slider tick.
    function save() {
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", root.path.substring(0, root.path.lastIndexOf("/"))]);
            view.writeAdapter();
        }
    }

    FileView {
        id: view
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.loaded = true
        onLoadFailed: root.loaded = true    // no file yet: defaults apply
        onAdapterUpdated: root.save()

        JsonAdapter {
            id: adapter

            property bool doNotDisturb: false
            property bool caffeine: false
            property bool use24h: true
            property bool blur: true
            property bool showSeconds: false
            property bool showSysStats: true
            property bool showNetSpeed: true
            property bool darkMode: true
            property bool nightLight: false
            property int nightLightTemp: 4000
            property bool autoRotate: false
            property string wallpaper: "/usr/share/backgrounds/shani/shani-shell.png"
            property string terminal: "foot"
            property bool dock: true
            property bool dockAutoHide: false
            // desktop-entry ids, in order; ones not installed are skipped
            property list<string> dockPinned: ["org.gnome.Nautilus", "firefox", "foot", "dev.shani.cassini", "shani-chronoa", "org.gnome.TextEditor"]
            property string recordingsDir: ""   // "" -> $XDG_VIDEOS_DIR or ~/Videos/Recordings

            // idle stages, seconds; 0 turns a stage off. *Battery applies on battery.
            property int dimAfter: 240
            property int lockAfter: 300
            property int screenOffAfter: 360
            property int suspendAfter: 0
            property int lockAfterBattery: 180
            property int screenOffAfterBattery: 240
            property int suspendAfterBattery: 600
            property bool lockBeforeSuspend: true
            property bool reduceMotion: false
            // screen keyboard languages, in the order the globe key cycles them
            property list<string> oskLanguages: ["en", "mr"]
        }
    }
}
