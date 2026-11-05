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
        d.touchpadOff ? "        off" : "",
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
        d.tpMiddleEmulation ? "        middle-emulation" : "",
        d.tpDragLock ? "        drag-lock" : "",
        "        tap-button-map \"" + d.tpTapButtonMap + "\"",
        "    }",
        "    mouse {",
        d.mouseNaturalScroll ? "        natural-scroll" : "",
        d.leftHanded ? "        left-handed" : "",
        "        accel-speed " + d.mouseSpeed.toFixed(2),
        "        accel-profile \"" + d.mouseAccel + "\"",
        "        scroll-factor " + d.mouseScroll,
        "    }",
        // a drawing tablet and a touchscreen: which screen each one draws on
        d.tabletOutput || d.tabletLeftHanded ? "    tablet {" : "",
        // "@focused": niri 26.04's map-to-focused-output, the screen being worked on
        d.tabletOutput === "@focused" ? "        map-to-focused-output" : d.tabletOutput ? "        map-to-output " + JSON.stringify(d.tabletOutput) : "",
        d.tabletLeftHanded ? "        left-handed" : "",
        d.tabletOutput || d.tabletLeftHanded ? "    }" : "",
        d.touchOutput ? "    touch {\n        map-to-output " + JSON.stringify(d.touchOutput) + "\n    }" : "",
        d.winFocusFollowsMouse ? "    focus-follows-mouse max-scroll-amount=\"0%\"" : "",
        "}",
        // windows
        "layout {",
        "    gaps " + d.winGaps,
        "    default-column-width { proportion " + Number(d.winDefaultWidth).toFixed(2) + "; }",
        "    focus-ring {",
        d.winFocusRing > 0 ? "        width " + d.winFocusRing : "        off",
        // the shell's accent (wallpaper-derived too), not the config's fixed colour
        d.winFocusRing > 0 ? "        active-color \"" + String(Theme.accent).slice(0, 7) + "\"" : "",
        "    }",
        "}",
        d.winAnimations && !d.reduceMotion ? "" : "animations {\n    off\n}",
        // niri encodes PNG or JPEG by the file extension; other formats (WebP, JPEG-XL) fall back to PNG.
        "screenshot-path \"" + (d.screenshotDir || "~/Pictures/Screenshots").replace(/"/g, "") + "/Screenshot from %Y-%m-%d %H-%M-%S." + (d.screenshotFormat === "jpeg" ? "jpg" : "png") + "\"",
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
        // edge-drag gestures: dragging a window to a screen edge scrolls the
        // view or switches workspaces; niri's hot corners stay off (the shell
        // has its own), so the shell is the only thing that opens them
        "gestures {",
        "    hot-corners {",
        "        off",
        "    }",
        d.dndEdgeViewScroll ? "    dnd-edge-view-scroll" : "",
        d.dndEdgeWorkspaceSwitch ? "    dnd-edge-workspace-switch" : "",
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
            // NiriConfig keeps the file as it was, and puts it back if niri cannot read this
            NiriConfig.write(root.path, root.kdl, Tr.t("keyboard, mouse and screens"));
        }
    }
}
