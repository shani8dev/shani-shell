.pragma library
// Ribbon viewport indicator (from niri-ribbon): where the visible part of a
// scrollable workspace sits in the whole horizontal row, as fractions.
// Pure functions of niri's window/workspace/output data — easy to unit test.

// One column width per scrolling column index; tiled windows only.
function columns(windows, workspaceId) {
    const byCol = {};
    for (const w of windows) {
        if (!w || w.workspace_id !== workspaceId || w.is_floating) continue;
        const L = w.layout || {};
        const p = L.pos_in_scrolling_layout;
        const t = L.tile_size;
        if (!p || !t) continue;
        const col = p[0];
        byCol[col] = Math.max(byCol[col] || 0, t[0] || 0);
    }
    return byCol;
}

// ratioStart/ratioWidth of the visible viewport, plus the active window's
// footprint relative to the whole ribbon (all clamped to 0..1).
//  windows:    Niri.windows values
//  workspace:  the active workspace for the output (needs .id)
//  outputWidth: Displays.outputs[].width (logical px)
//  gaps:       px between columns (Settings.data.winGaps)
//  anchor:     "fit" (niri default `center-focused-column never`) | "center"
//  focusedId:  focused window id (for the active-window marker)
//  memory:     previous { position, output } for the workspace (caller persists it)
function computeRatios(windows, workspace, outputWidth, gaps, anchor, focusedId, memory) {
    if (!workspace || !outputWidth)
        return { start: 0, width: 1, activeStart: 0, activeWidth: 0 };
    const byCol = columns(windows, workspace.id);
    const idxs = Object.keys(byCol).map(Number).sort((a, b) => a - b);
    if (idxs.length === 0)
        return { start: 0, width: 1, activeStart: 0, activeWidth: 0 };

    const gap = Math.max(0, Number(gaps) || 0);
    const colX = {};
    let canvas = 0;
    for (let i = 0; i < idxs.length; i++) {
        colX[idxs[i]] = canvas;
        canvas += byCol[idxs[i]] + (i < idxs.length - 1 ? gap : 0);
    }
    canvas = Math.max(canvas, outputWidth);

    // preferred anchor: the FOCUSED window's reported on-screen x tells us the
    // exact scroll offset (reportedViewPos = columnCanvasX - reportedX)
    let viewPos = null;
    const focusAnchor = windows.find(w => w && w.workspace_id === workspace.id && w.is_focused);
    const anchorCandidates = focusAnchor ? [focusAnchor] : windows;
    for (const w of anchorCandidates) {
        if (!w || w.workspace_id !== workspace.id || w.is_floating) continue;
        const L = w.layout || {};
        const p = L.pos_in_scrolling_layout, t = L.tile_pos_in_workspace_view;
        if (!p || !t || colX[p[0]] === undefined || t[0] === null || t[0] === undefined) continue;
        viewPos = colX[p[0]] - t[0];
        break;
    }
    if (viewPos === null) {
        const active = windows.find(w => w && w.workspace_id === workspace.id && w.is_focused);
        const fCol = active && active.layout ? active.layout.pos_in_scrolling_layout : null;
        const fIdx = fCol ? fCol[0] : idxs[idxs.length - 1];
        const fW = byCol[fIdx] || 0;
        if (anchor === "center") {
            viewPos = (colX[fIdx] || 0) + fW / 2 - outputWidth / 2;
        } else {
            // fit: keep the remembered position, expand only to reveal the focus
            const padding = Math.min(Math.max(0, (outputWidth - fW) / 2), gap);
            const left = (colX[fIdx] || 0) - padding;
            const right = (colX[fIdx] || 0) + fW + padding - outputWidth;
            const prev = memory && memory.position;
            if (prev !== undefined && prev !== null && left <= prev && prev <= right) viewPos = prev;
            else if (fW >= outputWidth) viewPos = colX[fIdx] || 0;
            else viewPos = left;
        }
    }
    const maxPos = Math.max(0, canvas - outputWidth);
    viewPos = Math.max(0, Math.min(maxPos, viewPos || 0));

    let start = viewPos / canvas;
    let width = outputWidth / canvas;
    if (width < 0.01) width = 0.01;
    if (start + width > 1) start = 1 - width;
    start = Math.max(0, start);

    // active window footprint, clipped to the visible range
    const act = windows.find(w => w && w.id === focusedId && w.workspace_id === workspace.id);
    let aStart = start, aWidth = 0;
    let aCol = act && act.layout ? act.layout.pos_in_scrolling_layout : null;
    if (aCol && colX[aCol[0]] !== undefined) {
        const ax = colX[aCol[0]] / canvas;
        const aw = (byCol[aCol[0]] || 0) / canvas;
        aStart = Math.max(start, ax);
        const aEnd = Math.min(start + width, ax + aw);
        aWidth = Math.max(0, aEnd - aStart);
    }
    return { start: start, width: width, activeStart: aStart, activeWidth: aWidth };
}
