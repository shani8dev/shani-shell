.pragma library
// Proportional workspace map (from niri-workspace-preview): lay out a
// workspace's tiled windows as rectangles whose widths come from column
// widths and heights from tile heights, with one shared scale so the aspect
// ratio is preserved. Floating windows are returned separately.

// Split a workspace's windows into tiled columns and floating windows.
//  windows: all Niri.windows values
//  wsId:    the workspace id
// Returns { columns: [{ index, width, windows: [...] }], floating: [...] }
function group(windows, wsId) {
    const byCol = {};
    const floating = [];
    for (const w of windows) {
        if (!w || w.workspace_id !== wsId) continue;
        const L = w.layout || {};
        const pos = L.pos_in_scrolling_layout;
        const size = L.tile_size;
        if (w.is_floating || !pos || !size) {
            floating.push(w);
            continue;
        }
        const col = pos[0];
        if (!byCol[col]) byCol[col] = { index: col, width: 0, windows: [] };
        byCol[col].width = Math.max(byCol[col].width, size[0] || 0);
        byCol[col].windows.push({ window: w, h: size[1] || 0, row: pos[1] || 0 });
    }
    const cols = Object.keys(byCol).map(k => byCol[k]).sort((a, b) => a.index - b.index);
    for (const c of cols) c.windows.sort((a, b) => a.row - b.row);
    return { columns: cols, floating: floating };
}

// The scale that fits the whole layout into innerWidth x innerHeight.
function scaleFor(groups, innerWidth, innerHeight, gap) {
    let rawW = 0, rawH = 0, maxRows = 0;
    for (const c of groups.columns) {
        rawW += c.width;
        rawH = Math.max(rawH, c.windows.reduce((s, w) => s + w.h, 0));
        maxRows = Math.max(maxRows, c.windows.length);
    }
    const gapW = gap * Math.max(0, groups.columns.length - 1);
    const gapH = gap * Math.max(0, maxRows - 1);
    const sx = rawW > 0 ? (innerWidth - gapW) / rawW : 1;
    const sy = rawH > 0 ? (innerHeight - gapH) / rawH : 1;
    return Math.max(0.001, Math.min(sx, sy));
}

// Rectangles for the tiled windows, in local coordinates of a frame of
// innerWidth x innerHeight. Each is { x, y, w, h, window, focused }.
function rects(groups, innerWidth, innerHeight, gap) {
    const s = scaleFor(groups, innerWidth, innerHeight, gap);
    const out = [];
    let x = 0;
    for (const c of groups.columns) {
        let y = 0;
        const cw = Math.max(1, c.width * s);
        for (const w of c.windows) {
            const h = Math.max(1, w.h * s);
            out.push({ x: x, y: y, w: cw, h: h, window: w.window, focused: !!w.window.is_focused });
            y += h + gap;
        }
        x += cw + gap;
    }
    return out;
}
