pragma Singleton
// A laptop's desktop layout follows its desk (docs/FORM-FACTORS.md step 5).
// Docked (a monitor plugged in) and on its own, the laptop each keeps the
// layout the owner last used there: the dock, the bar, the desktop widgets and
// icons, the window gaps and width, hot corners (what LayoutSwitcher's presets
// set). Nothing to choose: the first time in a state the layout stays as it is
// and is remembered from then on; change it while docked and undocking brings
// the other one back.
//
// Only on a machine with a built-in panel: a desktop is never "undocked", and a
// screen that is its own (a TV on HDMI) does not change the laptop's layout.
import Quickshell
import QtQuick
import qs.Common
import "DisplayModes.js" as DisplayModes

Singleton {
    id: root
    // the settings a layout preset owns: the ones carried between docks
    readonly property var keys: ["dock", "dockVisibility", "barVisibility", "dockIconSize", "desktopWidgets", "desktopIcons",
        "deskStacks", "winGaps", "winFocusRing", "winDefaultWidth", "winFocusFollowsMouse", "assistiveTouch",
        "showSysStats", "hotCornerTopLeft", "hotCornerTopRight", "hotCornerBottomLeft", "hotCornerBottomRight"]
    property string forced: ""            // "docked" / "alone": the tests (a nested niri has no panel to undock)
    readonly property bool hasPanel: Displays.outputs.some(o => DisplayModes.internal(o.name))
    readonly property string state: {
        if (forced !== "") return forced;
        if (!hasPanel) return "";
        return Displays.outputs.some(o => !DisplayModes.internal(o.name) && o.on) ? "docked" : "alone";
    }
    property string was: ""               // the state last followed
    property int switches: 0              // the tests
    // what this state's layout is: the settings as they are
    function snapshot() {
        const o = {};
        for (const k of keys) {
            const v = Settings.data[k];
            o[k] = v && typeof v === "object" ? JSON.parse(JSON.stringify(v)) : v;
        }
        return o;
    }
    onStateChanged: Qt.callLater(follow)
    function follow() {
        if (!Settings.loaded || !Settings.data.layoutFollowsDock) { was = state; return; }
        const all = Object.assign({}, Settings.data.layoutByDock || {});
        if (was !== "" && state !== "" && was !== state) {
            all[was] = snapshot();        // what it was in the state we are leaving
            const next = all[state];      // and what it was in the one we are entering
            if (next) {
                for (const k of keys)
                    if (next[k] !== undefined) Settings.data[k] = next[k];
                switches++;
            }
            Settings.data.layoutByDock = all;
        }
        was = state;
    }
    Connections {
        target: Settings
        function onLoadedChanged() { if (Settings.loaded) root.was = root.state }
    }
}