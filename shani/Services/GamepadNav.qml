pragma Singleton
// A game controller moves around the desktop: the d-pad and left stick are the
// arrows, A is Enter, B is Escape (bridge/gamepad.py nav types them with wtype);
// X opens the menu of what is focused (the Menu key) or the window menu, Y and
// Guide the launcher, Start the sidebar, Select the overview, LB / RB the
// previous / next workspace (inside a shell surface: its previous / next
// section, Tab). Every shell surface answers arrows and Enter
// (Common/KeyFocus), so this is all it takes. For what arrows cannot reach (a web
// page, a canvas) the right stick moves a pointer and the triggers click (RT left,
// LT right) - a virtual mouse the reader makes through uinput, when it can.
// It runs only while the setting is on, a controller is connected and no window
// is fullscreen (a game has the controller then). The reader is started and
// stopped by controllers coming and going (Plugged's udev events), never polled;
// it reads without grabbing, so a game in a window still gets every press.
// The first time it drives the desktop, a one-time hint says how.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_GAMEPAD_TOOL") || "/usr/lib/shani-shell/gamepad.py"
    property int controllers: 0
    readonly property var top: ToplevelManager.activeToplevel
    readonly property bool fullscreen: top !== null && Boolean(top.fullscreen)
    // InputPlumber, when it manages the controllers, hands the presses over itself (Services/InputPlumber)
    readonly property bool wanted: Settings.loaded && Settings.data.gamepadNav && controllers > 0 && !fullscreen && !InputPlumber.managing
    readonly property bool running: reader.running
    property string lastAction: ""        // for the tests
    property bool pointer: false          // the reader has its virtual mouse

    function count() { list.running = true; }
    Component.onCompleted: count()
    // a controller came or went: count again, and a new one is read from the start
    Connections {
        target: Plugged
        function onControllerRevChanged() { reader.running = false; root.count(); restart.restart(); }
    }
    Timer { id: restart; interval: 300; onTriggered: reader.running = root.wanted }
    onWantedChanged: reader.running = wanted
    Process {
        id: list
        command: ["python3", root.tool, "list"]
        stdout: StdioCollector { onStreamFinished: { try { root.controllers = JSON.parse(text).length; } catch (e) { root.controllers = 0; } } }
    }

    // a shell surface with the keyboard: X is the Menu key there, else the window menu
    readonly property bool shellHasKeys: Ui.controlCenter || Ui.settingsOpen || Ui.dockFocus || Ui.barFocus || Ui.launcher || Ui.windowMenu
    function act(a) {
        lastAction = a;
        if (a.startsWith("osk-")) {
            Osk.pad(a.slice(4));
            return;
        }
        if (a === "pointer") {
            root.pointer = true;
        } else if (a === "used") {
            if (!Settings.data.gamepadHintDone) {
                Settings.data.gamepadHintDone = true;
                Quickshell.execDetached(["notify-send", "-a", Tr.t("Game controller"), "-i", "input-gaming",
                    Tr.t("Your controller moves around the desktop"),
                    root.pointer ? Tr.t("A selects, B goes back, Start opens Quick Settings. The right stick moves the pointer; RT clicks.")
                                 : Tr.t("A selects, B goes back, Start opens Quick Settings.")]);
            }
        } else if (a === "menu") {
            if (root.shellHasKeys)
                Quickshell.execDetached(["wtype", "-k", "Menu"]);
            else if (Niri.focusedWindow) {
                Ui.windowMenuX = 200;
                Ui.windowMenu = true;
            } else
                Ui.desktopMenu = true;
        } else if (a === "launcher") {
            Ui.closeAll();
            Ui.toggleLauncher("");
        } else if (a === "sidebar")
            Ui.toggleControlCenter();
        else if (a === "overview")
            Niri.action("toggle-overview");
        // LB / RB: in a shell surface the previous / next section (Tab, which
        // a controller lacks - Quick Settings' notifications were 30-odd
        // presses of Down away); on the desktop the workspace above / below
        else if (a === "workspace-prev")
            root.shellHasKeys ? Quickshell.execDetached(["wtype", "-M", "shift", "-k", "Tab", "-m", "shift"]) : Niri.action("focus-workspace-up");
        else if (a === "workspace-next")
            root.shellHasKeys ? Quickshell.execDetached(["wtype", "-k", "Tab"]) : Niri.action("focus-workspace-down");
    }
    // the screen keyboard open: the reader sends the pad's presses here for its keys
    // instead of typing arrows into the app behind it (bridge/gamepad.py nav)
    function tellOsk() { if (reader.running) reader.write(Osk.shown && !Lock.locked ? "osk on\n" : "osk off\n"); }
    Connections { target: Osk; function onShownChanged() { root.tellOsk(); } }
    Connections { target: Lock; function onLockedChanged() { root.tellOsk(); } }
    Process {
        id: reader
        command: ["python3", root.tool, "nav"]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => { if (line === "ready") root.tellOsk(); else root.act(line.trim()); } }
        // every controller gone (or the reader failed): counted again, never retried in a loop
        onExited: { root.pointer = false; root.count(); }
    }
}
