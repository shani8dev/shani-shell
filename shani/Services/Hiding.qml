pragma Singleton
// When the bar and the dock step aside: each has "always", "smart" or "hide"
// (Settings barVisibility / dockVisibility). Smart is Plank's intelligent hide
// and Dash-to-Dock's intellihide - the default most people keep: it stays in
// view, keeping its space, and steps aside only while a window actually
// touches it (here: a floating window over it; tiled windows sit inside the
// space it keeps and fullscreen ones cover it anyway). Pointer at the edge, a
// menu or a drag, an app asking for attention or the overview bring it back.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    // the bars' state, per screen, for the Island (which rides on the bar)
    property var barShown: ({})
    function setBarShown(output, on) {
        if (root.barShown[output] === on)
            return;
        const o = Object.assign({}, root.barShown);
        o[output] = on;
        root.barShown = o;
    }
    property var dockShown: ({})
    function setDockShown(output, on) {
        if (root.dockShown[output] === on)
            return;
        const o = Object.assign({}, root.dockShown);
        o[output] = on;
        root.dockShown = o;
    }
    // whether each screen's dock base fits its surface (Dock.baseFits; the tests read it)
    property var dockFits: ({})
    function setDockFits(output, on) {
        if (root.dockFits[output] === on)
            return;
        const o = Object.assign({}, root.dockFits);
        o[output] = on;
        root.dockFits = o;
    }
    // an app asking for attention brings a smart dock back, as Plank does
    readonly property bool urgent: Object.values(Niri.windows).some(w => w.is_urgent)

    // does a floating window on this screen's workspace reach into the top or
    // bottom `band` px, over the part of the edge [x0, x1] the bar or dock takes?
    // height is the screen's. A picture-in-picture in a far corner is beside the
    // dock, not on it (it hid the dock when only the height was looked at).
    function covered(output, edge, band, height, x0, x1) {
        const ws = Niri.workspacesOn(output).find(w => w.is_active);
        if (!ws)
            return false;
        return Object.values(Niri.windows).some(w => {
            if (w.workspace_id !== ws.id)
                return false;
            const l = w.layout;
            if (!w.is_floating)
                return false;           // tiled: kept out of the edge by the space the bar/dock reserves
            if (!l || !l.tile_pos_in_workspace_view || !l.tile_size)
                return false;
            const left = l.tile_pos_in_workspace_view[0], right = left + l.tile_size[0];
            if (x1 !== undefined && (right <= x0 || left >= x1))
                return false;
            const top = l.tile_pos_in_workspace_view[1], bottom = top + l.tile_size[1];
            // niri keeps floating windows out of the reserved space, so one pushed
            // against the bar or dock stops exactly at its edge: that is touching
            return edge === "top" ? top <= band : bottom >= height - band;
        });
    }
}
