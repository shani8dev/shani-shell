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
import Quickshell.Io
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
        return FF.detect({ name: name, physical: o ? o.physical : [0, 0], label: o ? o.label : "" }, root.input, "");
    }
    readonly property var screens: {
        const chosen = Settings.data.formFactors || {};
        const scales = Settings.data.formFactorScales || {};
        const m = {};
        for (const o of Displays.outputs) {
            const p = FF.detect({ name: o.name, physical: o.physical, label: o.label }, root.input, root.forced || chosen[o.name] || "");
            m[o.name] = { profile: p, scale: FF.scale(p, scales[o.name]) };
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
    function chooseScale(name, scale) {
        if (!name) return;
        const m = Object.assign({}, Settings.data.formFactorScales || {});
        if (scale === "auto")
            delete m[name];
        else if (typeof scale === "number" && isFinite(scale) && scale >= 1 && scale <= 2)
            m[name] = scale;
        else
            return;
        Settings.data.formFactorScales = m;
    }
    // which edge this screen's bar is on ("top" or "bottom"): the owner's
    // choice, else the kind's own - a board's is at the bottom
    // the left workspace rail: not on a phone (no room), a ten-foot screen, or a
    // projector (what the room sees is what is presented)
    function hasRail(name) { const p = of(name).profile; return p !== "phone" && p !== "projector" && !tenFootKind(p); }
    function barEdge(name) { return FF.barEdge(of(name).profile, Settings.data.barEdge); }
    readonly property string focusedBarEdge: barEdge(Niri.focusedOutput || "")
    // seen from across a room or at arm's length, driven by a remote or a pad:
    // the TV home, Guide is Home, the ⋯ button opens the quick panel
    function tenFootKind(p) { return p === "tv" || p === "handheld"; }
    readonly property bool tenFoot: tenFootKind(focused.profile)
    readonly property var focused: of(Niri.focusedOutput || (Displays.outputs[0] || {}).name || "")
    onFocusedChanged: {
        Ui.formFactor = focused.profile;
        Ui.uiScale = focused.scale;
    }
    Component.onCompleted: { Ui.formFactor = focused.profile; Ui.uiScale = focused.scale; }

    // a handheld's sideways panel turned the right way, once a session, unless the
    // owner set the turn in Settings > Displays or the screen turns itself (auto-rotate)
    property string product: Quickshell.env("SHANI_DMI_PRODUCT") || ""
    property bool turned: false
    property bool productKnown: product !== ""
    function turnPanel() {
        if (turned || !productKnown || Settings.data.autoRotate) return;
        const chosen = Settings.data.displays || {};
        for (const o of Displays.outputs) {
            if ((chosen[o.name] || {}).transform || (o.transform && o.transform !== "normal")) continue;
            const pref = (o.modes || []).find(m => m.preferred) || (o.modes || [])[0];
            const t = FF.panelTurn(product, { name: o.name, nativeMode: pref ? [pref.w, pref.h] : null }, (screens[o.name] || {}).profile);
            if (t) {
                turned = true;
                Quickshell.execDetached(["niri", "msg", "output", o.name, "transform", t]);
            }
        }
    }
    onScreensChanged: Qt.callLater(turnPanel)
    Process {
        running: !root.productKnown
        command: ["cat", "/sys/class/dmi/id/product_name"]
        stdout: StdioCollector { onStreamFinished: { root.product = text.trim(); root.productKnown = true; Qt.callLater(root.turnPanel); } }
    }
}
