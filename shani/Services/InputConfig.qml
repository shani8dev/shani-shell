pragma Singleton
// Touchpad, mouse and key repeat, for niri: the settings become
// ~/.config/niri/shani-input.kdl, which the desktop's niri config includes —
// niri reloads it the moment it changes. Written whole, through a temporary
// file and a rename, so niri never reads half of it.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri/shani-input.kdl"
    readonly property var d: Settings.data
    readonly property string kdl: Settings.loaded ? [
        "// written by shani-shell: Settings > Keyboard & input. Edits here are replaced.",
        "input {",
        "    keyboard {",
        // the person's layouts; none chosen: niri follows the system keymap (localed)
        d.kbLayouts.length ? "        xkb {" : "",
        d.kbLayouts.length ? "            layout \"" + Array.from(d.kbLayouts).map(l => l.split("+")[0]).join(",") + "\"" : "",
        d.kbLayouts.length ? "            variant \"" + Array.from(d.kbLayouts).map(l => l.split("+")[1] || "").join(",") + "\"" : "",
        d.kbLayouts.length > 1 && d.kbSwitch ? "            options \"" + d.kbSwitch + "\"" : "",
        d.kbLayouts.length ? "        }" : "",
        "        repeat-delay " + d.keyRepeatDelay,
        "        repeat-rate " + d.keyRepeatRate,
        "    }",
        "    touchpad {",
        d.tapToClick ? "        tap" : "",
        d.typingGuard ? "        dwt" : "",
        d.naturalScroll ? "        natural-scroll" : "",
        d.leftHanded ? "        left-handed" : "",
        "        accel-speed " + d.touchpadSpeed.toFixed(2),
        "    }",
        "    mouse {",
        d.mouseNaturalScroll ? "        natural-scroll" : "",
        d.leftHanded ? "        left-handed" : "",
        "        accel-speed " + d.mouseSpeed.toFixed(2),
        "    }",
        "}",
        // the screens (Displays)
        Displays.kdl,
        // the pointer, niri's own (apps get it from Appearance)
        "cursor {",
        "    xcursor-theme \"" + d.cursorTheme + "\"",
        "    xcursor-size " + d.cursorSize,
        "}",
        ""
    ].filter(l => l !== "").join("\n") + "\n" : ""

    onKdlChanged: if (kdl) write.restart()
    Timer {
        id: write
        interval: 300                     // a few switches flipped together: one write
        onTriggered: {
            save.command = ["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s" "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", root.path, root.kdl];
            save.running = true;
        }
    }
    Process { id: save }
}
