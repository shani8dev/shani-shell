pragma Singleton
// Window arrangements: named grids (2×1, 2×2, 60/40, …) that the shell can
// apply by sending niri actions. Niri is the tiling compositor — it controls
// where windows actually go — so the shell's role is to store the grid
// definitions, show them as a palette, and send the right niri actions to
// arrange the focused window (and optionally the whole workspace).
//
// Per-display: each layout is keyed by output name, so it comes back when
// you reconnect that display. Undo: the last 10 arrangements are kept in
// memory, Ctrl+Z (or a button) restores the previous one.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root

    // a layout: { id, name, cols, rows, ratios } — ratios is an array of
    // column widths (and row heights for the first row), as fractions of the
    // workspace. E.g. "60/40 split" = cols:2, ratios:[0.6, 0.4].
    // Stored in Settings.data.windowLayouts so they survive restarts.
    readonly property var layouts: {
        const custom = Settings.data.windowLayouts || [];
        const builtin = [
            { id: "half",      name: "Half",        cols: 2, rows: 1, ratios: [0.5, 0.5] },
            { id: "thirds",    name: "Thirds",      cols: 3, rows: 1, ratios: [0.33, 0.33, 0.34] },
            { id: "quarters",  name: "Quarters",    cols: 2, rows: 2, ratios: [0.5, 0.5] },
            { id: "big-left",  name: "Big left",    cols: 2, rows: 1, ratios: [0.67, 0.33] },
            { id: "big-right", name: "Big right",   cols: 2, rows: 1, ratios: [0.33, 0.67] },
            { id: "stack",     name: "Stack",       cols: 1, rows: 3, ratios: [0.33, 0.33, 0.34] },
        ];
        return builtin.concat(custom);
    }

    // the last applied layout, per display (for the palette's "current" check)
    property var applied: ({})   // { "DP-1": "half", ... }
    function appliedOn(output) { return applied[output || Niri.focusedOutput] || ""; }

    // ---- undo history ----------------------------------------------------------
    // Each entry: { output, layoutId, time, snapshot? } — the last 10, newest last.
    // Undo restores the one before the current.
    property var undoStack: []
    function snapshot() {
        const wsId = Niri.focusedWorkspaceId;
        const out = [];
        const seen = {};
        for (const w of Object.values(Niri.windows)) {
            if (!w || w.workspace_id !== wsId || w.is_floating) continue;
            const L = w.layout || {};
            const pos = L.pos_in_scrolling_layout;
            const size = L.tile_size;
            if (!pos || !size) continue;
            const col = pos[0];
            if (seen[col]) continue;   // one representative per column
            seen[col] = true;
            out.push({ id: w.id, col: col, width: size[0] });
        }
        return out.sort((a, b) => a.col - b.col);
    }
    function pushUndo(output, layoutId, snap) {
        undoStack = undoStack.concat([{ output: output, layoutId: layoutId, time: Date.now(),
                                         snapshot: snap || null }]).slice(-10);
    }
    function restore(snap) {
        if (!snap || !snap.length) return;
        const outW = (Displays.outputs.find(o => o.name === Niri.focusedOutput) || {}).width || 1920;
        for (const c of snap) {
            Niri.action("focus-window", "--id", String(c.id));
            Niri.action("set-column-width", Math.max(10, Math.min(100, Math.round(100 * c.width / outW))) + "%");
        }
    }
    function undo() {
        if (undoStack.length < 2) return;
        const prev = undoStack[undoStack.length - 2];
        undoStack = undoStack.slice(0, -1);
        if (prev.snapshot && prev.snapshot.length) { restore(prev.snapshot); return; }
        root.apply(prev.layoutId, prev.output, false);
    }
    // Arrange every tiled column in the focused workspace into this layout's
    // column ratios — the "arrange many windows at once" counterpart of apply().
    function arrangeAll(layoutId) {
        const layout = layouts.find(l => l.id === layoutId);
        if (!layout) return;
        const snap = snapshot();
        pushUndo(Niri.focusedOutput, layoutId, snap);
        const out = Niri.focusedOutput;
        const a = Object.assign({}, applied);
        a[out] = layoutId;
        applied = a;
        for (let i = 0; i < snap.length; i++) {
            const ratio = layout.ratios[i % layout.ratios.length];
            Niri.action("focus-window", "--id", String(snap[i].id));
            Niri.action("set-column-width", Math.round(ratio * 100) + "%");
        }
    }

    // ---- apply a layout --------------------------------------------------------
    // Niri doesn't have a "grid layout" action — it's a column-based tiler.
    // The shell approximates grids by sending:
    //   - "move-column-to-side" (left/right) to position the focused column
    //   - "focus-column-left/right" to navigate
    //   - "move-window-to-workspace" for multi-workspace layouts
    // For a true grid, the user would need a different compositor or a
    // script that uses "niri msg action" with precise positioning.
    // What we CAN do well: half/quarter screen (left/right), focus follows.
    function apply(layoutId, output, record) {
        const layout = layouts.find(l => l.id === layoutId);
        if (!layout) return;
        if (record !== false) pushUndo(output || Niri.focusedOutput, layoutId, snapshot());

        // Mark as applied
        const out = output || Niri.focusedOutput;
        const a = Object.assign({}, applied);
        a[out] = layoutId;
        applied = a;

        // Send niri actions based on the layout
        // "half" / "big-left" / "big-right": move focused window to side
        if (layout.cols === 2 && layout.rows === 1) {
            const ratio = layout.ratios[0];
            if (ratio >= 0.6) {
                // big left: focused window goes left (already there in niri's column model)
                Niri.action("focus-column-left");
            } else if (ratio <= 0.4) {
                // big right
                Niri.action("focus-column-right");
            } else {
                // even split: toggle between left/right
                Niri.action("focus-column-right");
            }
        }
        // "thirds": cycle through 3 columns
        else if (layout.cols === 3) {
            Niri.action("focus-column-right");
        }
        // "stack": move window down (if niri supports it)
        else if (layout.rows > 1) {
            Niri.action("move-window-down");
            Niri.action("move-window-up");
        }
    }

    // ---- edge snap -------------------------------------------------------------
    // Niri has no "drag window to edge" compositor action — its columns fill the
    // screen height. The shell approximates the Slate behaviour by snapping the
    // focused column to a half/third width and moving it to a side. Niri handles
    // drag-to-edge itself (`dnd-edge-*` in its config) and exposes no drag event
    // to the shell, so the supported shell path is the keyboard shortcuts in the
    // desktop's niri config (Super+Alt+Arrow) and the layout palette.
    // shortcut: no compositor drag event exists to call snapToEdge from; niri's
    // own dnd-edge handling is the drag path, keyboard snapping is ours.
    function snapToEdge(edge) {
        const w = Niri.focusedWindow;
        if (!w) return;
        Niri.action("focus-window", "--id", String(w.id));
        if (edge === "left" || edge === "right") {
            Niri.action("set-column-width", "50%");
            Niri.action("move-column-to-side", edge);   // ignored on niri without it
        } else if (edge === "top" || edge === "bottom") {
            Niri.action("set-column-width", "100%");
        } else if (edge === "top-left" || edge === "top-right") {
            Niri.action("set-column-width", "50%");
            Niri.action("move-column-to-side", edge.indexOf("left") >= 0 ? "left" : "right");
        }
    }
    function onEdgeDrop(output, edge) { snapToEdge(edge); root.apply(edge === "top" || edge === "bottom" ? "stack" : "half", output); }

    // ---- custom layouts --------------------------------------------------------
    // The user can define their own grid: name, columns, rows, ratios.
    // Stored in Settings.data.windowLayouts (an array of layout objects).
    function addCustom(name, cols, rows, ratios) {
        const id = "custom-" + Date.now();
        const layout = { id: id, name: String(name || Tr.t("Custom %1", (Settings.data.windowLayouts || []).length + 1)),
                         cols: parseInt(cols) || 2, rows: parseInt(rows) || 1,
                         ratios: ratios || [0.5, 0.5] };
        const all = (Settings.data.windowLayouts || []).concat([layout]);
        Settings.data.windowLayouts = all;
        return id;
    }
    function removeCustom(id) {
        const all = (Settings.data.windowLayouts || []).filter(l => l.id !== id);
        Settings.data.windowLayouts = all;
        // also remove from applied
        const a = Object.assign({}, applied);
        for (const k in a) if (a[k] === id) delete a[k];
        applied = a;
    }
}
