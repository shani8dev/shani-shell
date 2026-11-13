pragma Singleton
// InputPlumber (shani-peripherals; org.shadowblip.InputPlumber on the system bus),
// through bridge/inputplumber.py: the controllers it manages - a handheld's
// built-in pad, or every controller when "manage all" is on - what each plays as
// in games (Xbox, DualSense, Steam Deck ...), and the controller borrowed from a
// game while the desktop is in use.
// While controller navigation is on, each controller is in InputPlumber's "pass"
// mode: everything goes to the game except the guide button, which comes here,
// opens Quick Settings and switches that controller to "always" - the game behind
// sees nothing while the desktop is driven. When the desktop's surfaces close, the
// controller goes back to "pass". Without InputPlumber, GamepadNav reads the
// controllers itself (bridge/gamepad.py), as before.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_INPUTPLUMBER_TOOL") || "/usr/lib/shani-shell/inputplumber.py"
    property bool running: false            // InputPlumber is on the bus
    property bool manageAll: false
    property var supported: []              // ["Microsoft X-Box Elite", ...]
    property var supportedIds: []           // ["xbox-elite", ...] (what TargetDevices takes)
    property var devices: []                // [{ path, name, profile, targets, intercept }]
    property string borrowed: ""            // the controller the desktop has from a game now
    property string lastEvent: ""           // for the tests
    property string error: ""
    readonly property bool managing: running && devices.length > 0
    readonly property bool navWanted: Settings.loaded && Settings.data.gamepadNav

    function send(obj) { watcher.write(JSON.stringify(obj) + "\n"); }
    function setTargets(path, ids) { send({ op: "targets", path: path, targets: ids }); }
    function setManageAll(on) { send({ op: "manageAll", on: on }); }
    function intercept(path, mode) { send({ op: "intercept", path: path, mode: mode }); }
    // what a controller plays as, in words: its first gamepad-kind target
    function playsAs(dev) {
        for (const t of dev.targets || []) {
            const i = supportedIds.indexOf(t);
            if (i >= 0) return supported[i] || t;
        }
        return "";
    }

    // navigation on: every controller in "pass" (the guide button comes here); off: none
    function applyMode() {
        if (!running) return;
        intercept("*", navWanted ? 1 : 0);
    }
    onNavWantedChanged: applyMode()
    onRunningChanged: applyMode()
    property int deviceCount: devices.length
    onDeviceCountChanged: applyMode()

    // the desktop's surfaces closed: the controller goes back to the game
    readonly property bool shellHasKeys: Ui.controlCenter || Ui.settingsOpen || Ui.dockFocus || Ui.barFocus || Ui.launcher || Ui.windowMenu
    onShellHasKeysChanged: giveBack.restart()
    Timer {
        id: giveBack
        interval: 250
        onTriggered: if (!root.shellHasKeys && root.borrowed !== "") { root.intercept(root.borrowed, root.navWanted ? 1 : 0); root.borrowed = ""; }
    }

    readonly property var keys: ({ ui_up: "Up", ui_down: "Down", ui_left: "Left", ui_right: "Right", ui_accept: "Return" })
    function input(ev) {
        lastEvent = ev.event;
        if (!(ev.value > 0)) return;                 // presses, not releases
        if (ev.event === "ui_guide" || ev.event === "ui_quick" || ev.event === "ui_quick2") {
            root.borrowed = ev.device || root.borrowed;
            if (root.shellHasKeys) Ui.closeAll(); else Ui.toggleControlCenter();
            return;
        }
        if (keys[ev.event]) { Quickshell.execDetached(["wtype", "-k", keys[ev.event]]); return; }
        if (ev.event === "ui_back") {
            if (root.shellHasKeys) Quickshell.execDetached(["wtype", "-k", "Escape"]);
            return;
        }
        // the rest, as a controller does without InputPlumber (Services/GamepadNav)
        const act = { ui_action: "menu", ui_context: "launcher", ui_option: "sidebar", ui_select: "overview",
                      ui_l1: "workspace-prev", ui_r1: "workspace-next" }[ev.event];
        if (act) GamepadNav.act(act);
        else if (ev.event === "ui_osk") Osk.toggle();
    }

    Process {
        id: watcher
        running: true
        stdinEnabled: true
        command: ["python3", root.tool, "watch"]
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.type === "state") {
                    root.running = m.running;
                    root.manageAll = m.manageAll;
                    root.supported = m.supported || [];
                    root.supportedIds = m.supportedIds || [];
                    root.devices = m.devices || [];
                } else if (m.type === "input") {
                    root.input(m);
                } else if (m.type === "error") {
                    root.error = m.error;
                }
            }
        }
    }
}
