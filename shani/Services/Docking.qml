pragma Singleton
// The desktop layout follows the situation the computer is in (docs/FORM-FACTORS.md):
// each situation keeps the layout last used in it, and one where the desktop
// layout does not work - a touch screen, a screen seen from across a room -
// starts in the layout made for it (Services/Layouts), the first time, with an
// Undo. The situations:
//
//   "docked"          a machine with a built-in panel and a monitor plugged in
//   "alone"           a laptop on its own
//   "alone:<kind>"    on its own as something else: a convertible folded into a
//                     "tablet", a "phone", a "handheld" (its panel's kind)
//   "screen:<kind>"   no built-in panel, its screen a "tv", a "board"...
//   "screen"          a desktop computer's own screen (or a projector)
//
// The first time as a laptop or docked, the layout stays as it is. Change the
// layout in a situation and leaving it remembers it there; coming back brings
// it back. Settings > Personalisation can turn the following off.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "DisplayModes.js" as DisplayModes
import "../Common/FormFactor.js" as FF

Singleton {
    id: root
    // the settings a layout owns: the ones carried between situations
    readonly property var keys: Layouts.keys
    // where the desktop layout does not work: these start in their own the first time
    readonly property var startsMadeFor: ["tablet", "phone", "handheld", "tv", "board"]
    property string forced: ""            // a situation the tests set (a nested niri has no panel to fold)
    readonly property var panel: Displays.outputs.find(o => DisplayModes.internal(o.name)) || null
    readonly property bool hasPanel: panel !== null
    readonly property string state: {
        if (forced !== "") return forced;
        if (hasPanel) {
            if (Displays.outputs.some(o => !DisplayModes.internal(o.name) && o.on)) return "docked";
            const k = FormFactor.of(panel.name).profile;
            return k === "laptop" || k === "computer" ? "alone" : "alone:" + k;
        }
        const first = Displays.outputs.find(o => o.on) || Displays.outputs[0];
        const k = first ? FormFactor.of(first.name).profile : "computer";
        return startsMadeFor.indexOf(k) >= 0 ? "screen:" + k : "screen";
    }
    // the kind of screen a situation is
    function kindOf(st) {
        if (st === "docked" || st === "screen" || st === "") return "computer";
        if (st === "alone") return "laptop";
        return st.split(":")[1] || "computer";
    }
    property string was: ""               // the situation last followed
    property int switches: 0              // the tests
    property string started: ""           // the situation that last got its made-for layout (the tests)
    function snapshot() { return Layouts.snapshot(); }
    onStateChanged: Qt.callLater(follow)
    function follow() {
        if (!Settings.loaded || !Settings.data.layoutFollowsDock) { was = state; return; }
        if (was === state) return;
        const all = Object.assign({}, Settings.data.layoutByDock || {});
        const leaving = snapshot();
        if (was !== "") all[was] = leaving;           // what it was in the situation we are leaving
        const next = state !== "" ? all[state] : null;
        if (next) {
            for (const k of keys)
                if (next[k] !== undefined) Settings.data[k] = next[k];
            switches++;
        } else if (state !== "") {
            startMadeFor(all, leaving);
        }
        Settings.data.layoutByDock = all;
        was = state;
    }
    // the first time in a situation the desktop layout does not suit: its own
    // layout, said so, with Undo and a way to choose another
    property var before: null
    function startMadeFor(all, prev) {
        const kind = kindOf(state);
        if (startsMadeFor.indexOf(kind) < 0) return;
        const p = Layouts.madeFor(kind);
        if (!p) return;
        before = prev;
        Layouts.put(p.set);
        Settings.data.layoutPreset = p.id;
        all[state] = snapshot();
        started = state;
        switches++;
        notice.command = ["notify-send", "-a", Tr.t("Screen and layout"), "-i", p.icon,
                          "-A", "undo=" + Tr.t("Undo"), "-A", "change=" + Tr.t("Choose another"),
                          Tr.t("The %1 layout", p.name),
                          Tr.t("Made for a %1. Your other layout comes back when you go back.", Tr.t(FF.label(kind)).toLowerCase())];
        notice.running = true;
    }
    Process {
        id: notice
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim();
                if (a === "undo" && root.before) {
                    Layouts.put(root.before);
                    const all = Object.assign({}, Settings.data.layoutByDock || {});
                    all[root.state] = root.snapshot();
                    Settings.data.layoutByDock = all;
                } else if (a === "change") {
                    Ui.closeAll();
                    Ui.layoutSwitcher = true;
                }
            }
        }
    }
    Connections {
        target: Settings
        function onLoadedChanged() {
            if (!Settings.loaded) return;
            // the very first start in a situation the desktop layout does not suit
            // (a phone, a handheld, a TV box, a board): its own layout from the start
            if (Settings.data.layoutFollowsDock && root.state !== "" && !(Settings.data.layoutByDock || {})[root.state]) {
                const all = Object.assign({}, Settings.data.layoutByDock || {});
                root.startMadeFor(all, root.snapshot());
                Settings.data.layoutByDock = all;
            }
            root.was = root.state;
        }
    }
}
