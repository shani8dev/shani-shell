pragma Singleton
// What kind of screen each output is - computer, laptop, tablet, handheld,
// phone, TV or classroom board - and how big the shell is drawn on it
// (docs/FORM-FACTORS.md, the rules in Common/FormFactor.js). Per screen: a
// laptop with a TV on HDMI is a laptop on its panel and a TV on the TV. It
// follows changes as they happen: a 2-in-1 folded into a tablet, a pad
// plugged in, a screen added, the owner's choice in Settings > Displays.
//
// The focused screen's answer goes to Ui.formFactor / Ui.uiScale, which is what
// Theme.ui and Theme.px() give every surface that opens on the focused screen;
// a surface on every screen (the bar, the dock) asks of(its screen's name).
// SHANI_FORM_FACTOR=<kind> sets every screen (the dev renders).
import Quickshell
import QtQuick
import qs.Common
import "../Common/FormFactor.js" as FF

Singleton {
    id: root
    readonly property string forced: Quickshell.env("SHANI_FORM_FACTOR") || ""
    readonly property var input: ({
        touch: InputKinds.touchscreen,
        tabletMode: TabletMode.known && TabletMode.on,
        keyboard: InputKinds.keyboard,
        // InputPlumber manages a handheld's built-in pad (every pad only when
        // "manage every controller" is on), so one managed pad is a built-in one
        builtinPad: InputPlumber.running && !InputPlumber.manageAll && InputPlumber.devices.length > 0
    })
    function detected(name) {
        const o = Displays.outputs.find(x => x.name === name);
        return FF.detect({ name: name, physical: o ? o.physical : [0, 0] }, root.input, "");
    }
    readonly property var screens: {
        const chosen = Settings.data.formFactors || {};
        const m = {};
        for (const o of Displays.outputs) {
            const p = FF.detect({ name: o.name, physical: o.physical }, root.input, root.forced || chosen[o.name] || "");
            m[o.name] = { profile: p, scale: FF.scale(p) };
        }
        return m;
    }
    function of(name) {
        return screens[name] || (forced ? { profile: forced, scale: FF.scale(forced) } : { profile: "computer", scale: 1.0 });
    }
    function choose(name, kind) {
        const m = Object.assign({}, Settings.data.formFactors || {});
        if (kind === "auto" || !kind)
            delete m[name];
        else
            m[name] = kind;
        Settings.data.formFactors = m;
    }
    readonly property var focused: of(Niri.focusedOutput || (Displays.outputs[0] || {}).name || "")
    onFocusedChanged: {
        Ui.formFactor = focused.profile;
        Ui.uiScale = focused.scale;
    }
    Component.onCompleted: { Ui.formFactor = focused.profile; Ui.uiScale = focused.scale; }
}
