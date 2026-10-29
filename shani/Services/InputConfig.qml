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
    readonly property string xkbOptions: [d.kbLayouts.length > 1 ? d.kbSwitch : "", d.kbCompose ? "compose:" + d.kbCompose : "", d.kbCaps]
        .filter(x => x).join(",")
    readonly property string kdl: Settings.loaded ? [
        "// written by shani-shell: Settings > Keyboard & input. Edits here are replaced.",
        "input {",
        "    keyboard {",
        // the person's layouts (none chosen: niri follows the system keymap,
        // localed) and xkb options: the layout switch, compose, Caps Lock
        d.kbLayouts.length || root.xkbOptions ? "        xkb {" : "",
        d.kbLayouts.length ? "            layout \"" + Array.from(d.kbLayouts).map(l => l.split("+")[0]).join(",") + "\"" : "",
        d.kbLayouts.length ? "            variant \"" + Array.from(d.kbLayouts).map(l => l.split("+")[1] || "").join(",") + "\"" : "",
        root.xkbOptions ? "            options \"" + root.xkbOptions + "\"" : "",
        d.kbLayouts.length || root.xkbOptions ? "        }" : "",
        d.numlock ? "        numlock" : "",
        "        repeat-delay " + d.keyRepeatDelay,
        "        repeat-rate " + d.keyRepeatRate,
        "    }",
        "    touchpad {",
        d.tapToClick ? "        tap" : "",
        d.typingGuard ? "        dwt" : "",
        d.naturalScroll ? "        natural-scroll" : "",
        d.leftHanded ? "        left-handed" : "",
        "        accel-speed " + d.touchpadSpeed.toFixed(2),
        "        accel-profile \"" + d.tpAccel + "\"",
        "        scroll-factor " + d.tpScroll,
        "        click-method \"" + d.tpClick + "\"",
        "        scroll-method \"" + d.tpScrollMethod + "\"",
        d.tpOffWithMouse ? "        disabled-on-external-mouse" : "",
        "    }",
        "    mouse {",
        d.mouseNaturalScroll ? "        natural-scroll" : "",
        d.leftHanded ? "        left-handed" : "",
        "        accel-speed " + d.mouseSpeed.toFixed(2),
        "        accel-profile \"" + d.mouseAccel + "\"",
        "        scroll-factor " + d.mouseScroll,
        "    }",
        d.winFocusFollowsMouse ? "    focus-follows-mouse max-scroll-amount=\"0%\"" : "",
        "}",
        // windows
        "layout {",
        "    gaps " + d.winGaps,
        "    default-column-width { proportion " + d.winDefaultWidth + "; }",
        "    focus-ring {",
        d.winFocusRing > 0 ? "        width " + d.winFocusRing : "        off",
        "    }",
        "}",
        d.winAnimations ? "" : "animations {\n    off\n}",
        "screenshot-path \"" + (d.screenshotDir || "~/Pictures/Screenshots").replace(/"/g, "") + "/Screenshot from %Y-%m-%d %H-%M-%S.png\"",
        // your own shortcuts: a command each
        Array.from(d.customBinds || []).length ? "binds {\n" + Array.from(d.customBinds).filter(b => /^[A-Za-z0-9+_]+$/.test(b.key) && b.command)
            .map(b => "    " + b.key + " hotkey-overlay-title=" + JSON.stringify(b.title || b.command) + " { spawn \"sh\" \"-c\" " + JSON.stringify(b.command) + "; }").join("\n") + "\n}" : "",
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
    // middle-click paste is the toolkit's: GTK reads this one switch
    Process {
        running: Settings.loaded
        command: ["gsettings", "set", "org.gnome.desktop.interface", "gtk-enable-primary-paste", String(root.d.middlePaste)]
        onCommandChanged: if (Settings.loaded) running = true
    }
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
