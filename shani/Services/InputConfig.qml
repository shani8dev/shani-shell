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
        root.kbLayouts().length || root.xkbOptions ? "        xkb {" : "",
        root.kbLayouts().length ? "            layout \"" + root.kbLayouts().map(l => l.split("+")[0]).join(",") + "\"" : "",
        root.kbLayouts().length ? "            variant \"" + root.kbLayouts().map(l => l.split("+")[1] || "").join(",") + "\"" : "",
        root.xkbOptions ? "            options \"" + root.xkbOptions + "\"" : "",
        root.kbLayouts().length || root.xkbOptions ? "        }" : "",
        d.numlock ? "        numlock" : "",
        // each window keeps the layout it was typed in (an English editor, a Marathi chat)
        d.kbPerWindow ? "        track-layout \"window\"" : "",
        "        repeat-delay " + root.boundedInt(d.keyRepeatDelay, 0, 10000),
        "        repeat-rate " + root.boundedInt(d.keyRepeatRate, 0, 1000),
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
        "        drag " + (d.tpDrag ? "true" : "false"),
        d.tpDwtp ? "        dwtp" : "",
        "    }",
        "    mouse {",
        d.mouseNaturalScroll ? "        natural-scroll" : "",
        d.leftHanded ? "        left-handed" : "",
        "        accel-speed " + d.mouseSpeed.toFixed(2),
        "        accel-profile \"" + d.mouseAccel + "\"",
        "        scroll-factor " + d.mouseScroll,
        // no wheel: hold the middle button and move
        d.mouseScrollButton ? "        scroll-method \"on-button-down\"" : "",
        d.mouseScrollButton && d.scrollButtonLock ? "        scroll-button-lock" : "",
        "    }",
        // a ThinkPad's red dot: scrolls with the middle button held, as libinput does
        "    trackpoint {",
        d.tpointNaturalScroll ? "        natural-scroll" : "",
        d.leftHanded ? "        left-handed" : "",
        "        accel-speed " + Number(d.tpointSpeed).toFixed(2),
        "        accel-profile \"" + d.tpointAccel + "\"",
        "    }",
        "    trackball {",
        d.tballNaturalScroll ? "        natural-scroll" : "",
        d.leftHanded ? "        left-handed" : "",
        "        accel-speed " + Number(d.tballSpeed).toFixed(2),
        "        accel-profile \"" + d.tballAccel + "\"",
        d.tballScrollButton ? "        scroll-method \"on-button-down\"" : "",
        d.tballScrollButton && d.scrollButtonLock ? "        scroll-button-lock" : "",
        "    }",
        // a drawing tablet and a touchscreen: which screen each one draws on
        root.tabletBlock ? "    tablet {" : "",
        // "@focused": the screen being worked on; "@window": the window being drawn in
        d.tabletOutput === "@focused" ? "        map-to-focused-output"
            : d.tabletOutput === "@window" ? "        map-to-focused-window"
            : d.tabletOutput ? "        map-to-output " + JSON.stringify(d.tabletOutput) : "",
        d.tabletLeftHanded ? "        left-handed" : "",
        root.matrix(d.tabletMatrix),
        root.tabletBlock ? "    }" : "",
        d.touchOutput || root.matrix(d.touchMatrix) ? "    touch {" : "",
        d.touchOutput ? "        map-to-output " + JSON.stringify(d.touchOutput) : "",
        root.matrix(d.touchMatrix),
        d.touchOutput || root.matrix(d.touchMatrix) ? "    }" : "",
        d.warpMouseToFocus ? "    warp-mouse-to-focus" : "",
        d.wsBackAndForth ? "    workspace-auto-back-and-forth" : "",
        // the power button: niri's (sleep) until Settings > Power chose for it - then logind's
        d.powerKeyByLogind ? "    disable-power-key-handling" : "",
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
        d.winFocusRing > 0 ? "        urgent-color \"" + String(Theme.danger).slice(0, 7) + "\"" : "",
        "    }",
        // tabs: a column's windows one at a time, with a strip of tabs at its side
        d.winTabbed ? "    default-column-display \"tabbed\"" : "",
        "    tab-indicator {",
        "        hide-when-single-tab",
        "        place-within-column",
        "        active-color \"" + String(Theme.accent).slice(0, 7) + "\"",
        "        urgent-color \"" + String(Theme.danger).slice(0, 7) + "\"",
        "    }",
        // where a dragged window will land
        "    insert-hint {",
        "        color \"" + String(Theme.accent).slice(0, 7) + "80\"",
        "    }",
        // heights a window steps through (Mod+Shift+R), as widths have
        "    preset-window-heights {",
        "        proportion 0.33333",
        "        proportion 0.5",
        "        proportion 0.66667",
        "    }",
        d.winEmptyAbove ? "    empty-workspace-above-first" : "",
        d.winStrutLeft || d.winStrutRight || d.winStrutTop || d.winStrutBottom
            ? "    struts {\n        left " + d.winStrutLeft + "\n        right " + d.winStrutRight + "\n        top " + d.winStrutTop + "\n        bottom " + d.winStrutBottom + "\n    }" : "",
        "}",
        // the overview: how small the workspaces get
        "overview {",
        "    zoom " + Number(d.overviewZoom).toFixed(2),
        "}",
        // middle-click paste off for every app, not only GTK's (the gsettings below)
        !d.middlePaste ? "clipboard {\n    disable-primary\n}" : "",
        // the lid and a convertible's fold, as niri sees them: told to the shell
        // (Services/Switches), which runs them even while the screen is locked
        "switch-events {",
        "    lid-close { spawn " + root.ipc("switchEvent", "lid-close") + "; }",
        "    lid-open { spawn " + root.ipc("switchEvent", "lid-open") + "; }",
        "    tablet-mode-on { spawn " + root.ipc("switchEvent", "tablet-on") + "; }",
        "    tablet-mode-off { spawn " + root.ipc("switchEvent", "tablet-off") + "; }",
        "}",
        // animations, shadows, corners and blur: WindowLook's shani-look.kdl
        // niri encodes PNG or JPEG by the file extension; other formats (WebP, JPEG-XL) fall back to PNG.
        "screenshot-path \"" + (d.screenshotDir || "~/Pictures/Screenshots").replace(/"/g, "") + "/Screenshot from %Y-%m-%d %H-%M-%S." + (d.screenshotFormat === "jpeg" ? "jpg" : "png") + "\"",
        // your own shortcuts: a command each (with the per-binding parameter, if any)
        Array.from(d.customBinds || []).length ? "binds {\n" + Array.from(d.customBinds).filter(b => /^[A-Za-z0-9+_]+$/.test(b.key) && b.command)
            .map(b => "    " + b.key + " hotkey-overlay-title=" + JSON.stringify(b.title || b.command) + " { spawn \"sh\" \"-c\" " + JSON.stringify(b.command + (b.param ? " " + String(b.param).trim() : "")) + "; }").join("\n") + "\n}" : "",
        // the screens (Displays)
        Displays.kdl,
        // the pointer, niri's own (apps get it from Appearance)
        "cursor {",
        "    xcursor-theme \"" + d.cursorTheme + "\"",
        "    xcursor-size " + d.cursorSize,
        d.cursorHideTyping ? "    hide-when-typing" : "",
        d.cursorHideIdle > 0 ? "    hide-after-inactive-ms " + (d.cursorHideIdle * 1000) : "",
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
        // Multi-GPU: pin the render device niri uses, so a laptop stays on
        // its integrated GPU instead of draining battery with the dGPU
        d.niriRenderDevice ? 'debug { render-drm-device "' + String(d.niriRenderDevice).replace(/"/g, "") + '" }' : "",
        ""
    ].filter(l => l !== "").join("\n") + "\n" : ""

    readonly property bool tabletBlock: !!(d && (d.tabletOutput || d.tabletLeftHanded || matrix(d.tabletMatrix)))
    // a calibration: six numbers (libinput's 2x3), or nothing
    function matrix(m) {
        const a = Array.from(m || []).map(Number);
        return a.length === 6 && a.every(x => isFinite(x)) ? "        calibration-matrix " + a.map(x => x.toFixed(6)).join(" ") : "";
    }
    // xkb ids only contain these; a stray quote from a hand-edited settings.json
    // must not turn the whole input include into KDL niri refuses to load
    function kbLayouts() {
        return Array.from(d.kbLayouts || []).filter(l => /^[A-Za-z0-9_+_-]+$/.test(String(l || "")));
    }
    // niri refuses the whole include for an out-of-range repeat value
    function boundedInt(v, lo, hi) {
        const n = Math.round(Number(v));
        return isFinite(n) ? Math.min(hi, Math.max(lo, n)) : lo;
    }
    // a niri spawn calling this shell's IPC (qs -p its directory: the installed one and a checkout's alike)
    function ipc(fn, arg) {
        return ["qs", "-p", Quickshell.shellDir, "ipc", "call", "shani", fn, arg].map(x => JSON.stringify(x)).join(" ");
    }

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
