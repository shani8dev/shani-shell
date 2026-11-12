pragma Singleton
// The terminal: which one opens (Settings > Apps & files), and foot in the
// desktop's colours.
//
//  - ~/.config/niri-xdg-terminals.list names the chosen terminal's desktop
//    entry, so Mod+Return (niri spawns xdg-terminal-exec) and "open in a
//    terminal" from any app open the same one the shell does.
//  - ~/.config/foot/foot.ini: the system foot.ini (shani-desktop-niri's, as an
//    include) with the desktop's colours over it - its background and text,
//    the accent for the cursor, the selection and links, its header colour for
//    the titlebar - for dark and for light. Open foot windows (the server's
//    and every lone one) switch with the desktop: SIGUSR1 is foot's dark, SIGUSR2
//    its light (measured on foot 1.28). The titlebar and accent are read when
//    foot starts: an idle foot server is stopped so the next window has them.
//
// Both files are written only while they are the shell's: a file without the
// shell's first line is a person's own and is never touched. Deleting that
// first line is how to keep one as your own.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string mark: "# written by shani-shell"
    readonly property string config: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string listPath: config + "/niri-xdg-terminals.list"
    readonly property string footPath: config + "/foot/foot.ini"
    readonly property string systemFoot: Quickshell.env("SHANI_SYSTEM_FOOT_INI") || "/etc/xdg/foot/foot.ini"

    // the terminals the picker knows by name; any other command is typed
    readonly property var known: [
        { cmd: "footclient", name: "Foot", note: Tr.t("instant: windows of one foot server"), desktop: "footclient.desktop" },
        { cmd: "foot", name: Tr.t("Foot, a process each"), note: Tr.t("a window that does not share a server"), desktop: "foot.desktop" },
        { cmd: "ghostty", name: "Ghostty", note: Tr.t("tabs, splits and pictures in the terminal"), desktop: "com.mitchellh.ghostty.desktop" },
        { cmd: "/var/lib/flatpak/exports/bin/com.mitchellh.ghostty", name: "Ghostty", note: Tr.t("tabs, splits and pictures in the terminal (Flatpak)"), desktop: "com.mitchellh.ghostty.desktop" },
        { cmd: "kitty", name: "kitty", note: "", desktop: "kitty.desktop" },
        { cmd: "alacritty", name: "Alacritty", note: "", desktop: "Alacritty.desktop" },
        { cmd: "wezterm", name: "WezTerm", note: "", desktop: "org.wezfurlong.wezterm.desktop" },
        { cmd: "ptyxis", name: "Ptyxis", note: "", desktop: "org.gnome.Ptyxis.desktop" },
        { cmd: "kgx", name: "Console", note: "", desktop: "org.gnome.Console.desktop" },
        { cmd: "gnome-terminal", name: "GNOME Terminal", note: "", desktop: "org.gnome.Terminal.desktop" },
        { cmd: "konsole", name: "Konsole", note: "", desktop: "org.kde.konsole.desktop" },
        { cmd: "xterm", name: "XTerm", note: "", desktop: "xterm.desktop" }
    ]
    function entryFor(cmd) {
        const k = known.find(t => t.cmd === cmd);
        return k ? k.desktop : (String(cmd).split("/").pop().split(" ")[0] + ".desktop");
    }

    readonly property string chosen: Settings.loaded ? (Settings.data.terminal || "footclient") : ""
    readonly property string listText: chosen ? root.mark + " (Settings > Apps & files). Delete this line to keep the file as your own.\n" + entryFor(chosen) + "\n" : ""

    function hex(c) { return [c.r, c.g, c.b].map(x => Math.round(x * 255).toString(16).padStart(2, "0")).join(""); }
    function mixHex(a, b, t) { return hex(Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)); }
    // the desktop's colours for the mode it is in now; the other mode keeps what
    // the system foot.ini (dark) or the light palette below says
    readonly property string modeColours: {
        const bg = Theme.bg, fg = Theme.text, acc = Theme.accent;
        return [
            "background=" + hex(bg),
            "foreground=" + hex(fg),
            "cursor=" + hex(bg) + " " + hex(acc),
            "selection-background=" + mixHex(bg, acc, 0.38),
            "selection-foreground=" + hex(fg),
            "urls=" + hex(acc)
        ].join("\n");
    }
    readonly property string footText: !Settings.loaded || !Settings.data.terminalThemed ? "" : [
        root.mark + ": foot in the desktop's colours (Settings > Apps & files).",
        "# Delete this first line to keep the file as your own: the shell then leaves it alone.",
        "include=" + root.systemFoot,
        "",
        "[main]",
        "initial-color-theme=" + (Theme.dark ? "dark" : "light"),
        "",
        "[colors-dark]",
        Theme.dark ? root.modeColours : "",
        "",
        // a light palette that reads on a light background (the system foot.ini has dark only)
        "[colors-light]",
        "alpha=0.96",
        "regular0=3b3a45", "regular1=c0392b", "regular2=2e7d32", "regular3=9a6700",
        "regular4=1f5fbf", "regular5=8e44ad", "regular6=0e7c86", "regular7=5f5b66",
        "bright0=6b6775", "bright1=e0503f", "bright2=3f9b45", "bright3=b58105",
        "bright4=3b7be0", "bright5=a35fc4", "bright6=16959f", "bright7=2a2730",
        Theme.dark ? "background=faf8f6\nforeground=2a2730" : root.modeColours,
        "",
        // the titlebar foot draws: the shell's own header colour and text
        "[csd]",
        "color=ff" + hex(Theme.surface1),
        "button-color=ff" + hex(Theme.text),
        ""
    ].join("\n")

    property string listState: ""     // "written" | "theirs" (the tests read these)
    property string footState: ""

    onListTextChanged: if (listText) listTimer.restart()
    onFootTextChanged: if (footText) footTimer.restart()
    Timer { id: listTimer; interval: 400; onTriggered: { listProc.running = false; listProc.running = true; } }
    Timer { id: footTimer; interval: 400; onTriggered: { footProc.running = false; footProc.running = true; } }

    // exit 0: written; 3: the file is a person's own, left alone
    readonly property string writeScript: 'f=$1; mark=$3
        if [ -e "$f" ] && ! head -n1 "$f" | grep -qF "$mark"; then exit 3; fi
        mkdir -p "${f%/*}" && printf "%s" "$2" > "$f.tmp" && mv "$f.tmp" "$f"'
    Process {
        id: listProc
        command: ["sh", "-c", root.writeScript, "sh", root.listPath, root.listText, root.mark]
        onExited: code => root.listState = code === 0 ? "written" : code === 3 ? "theirs" : "failed"
    }
    Process {
        id: footProc
        // then: open windows switch light/dark now; and a foot server with no
        // window left is stopped, so the next one (socket-activated) reads the
        // new colours - the titlebar and the accent are read when foot starts
        command: ["sh", "-c", root.writeScript + '\n        pkill -' + (Theme.dark ? "USR1" : "USR2") + ' -x foot
        [ "$4" = idle ] && systemctl --user stop foot-server.service 2>/dev/null; exit 0',
            "sh", root.footPath, root.footText, root.mark,
            Object.values(Niri.windows).some(w => w.app_id === "footclient") ? "busy" : "idle"]
        onExited: code => root.footState = code === 0 ? "written" : code === 3 ? "theirs" : "failed"
    }
}
