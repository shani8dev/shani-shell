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
    let runX = 0;
    for (const c of cols) { c._x = runX; runX += c.width + 4; }
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

// The visible viewport as a rectangle over the tiled map (niri-workspace-preview's
// viewport highlight). Uses the same anchor logic as Ribbon.js: a focused
// window's tile_pos_in_workspace_view gives the exact scroll offset; else a
// fit/center estimate. `canvasWidth` is the unscaled width of the columns.
function canvasWidth(groups, gap) {
    let w = 0;
    for (const c of groups.columns) w += c.width + gap;
    return Math.max(1, w);
}
function viewport(groups, outputWidth, gap, anchor, focusedId) {
    const cw = canvasWidth(groups, gap);
    if (cw <= outputWidth) return { x: 0, width: cw };
    let pos = null;
    const focus = (groups.columns || []).flatMap(c => c.windows).find(w => w.window && w.window.id === focusedId);
    if (focus && focus.window.layout && focus.window.layout.tile_pos_in_workspace_view) {
        let colX = 0;
        for (const c of groups.columns) {
            if (c.index === focus.window.layout.pos_in_scrolling_layout[0]) break;
            colX += c.width + gap;
        }
        pos = colX - focus.window.layout.tile_pos_in_workspace_view[0];
    }
    if (pos === null) {
        let fx = 0, fw = 0;
        for (const c of groups.columns) {
            if (c.windows.some(w => w.window && w.window.id === focusedId)) { fx = c._x || 0; fw = c.width; }
        }
        if (anchor === "center") pos = fx + fw / 2 - outputWidth / 2;
        else pos = fx;
    }
    pos = Math.max(0, Math.min(cw - outputWidth, pos));
    return { x: pos, width: Math.min(cw, outputWidth) };
}

// Floating windows, positioned from their absolute workspace-view coordinates.
// QML maps these into the map frame with the output's logical width/height.
function floatingRects(floating, outputW, outputH, frameW, frameH) {
    const sx = outputW > 0 ? frameW / outputW : 1;
    const sy = outputH > 0 ? frameH / outputH : 1;
    return (floating || []).map(w => {
        const L = w.layout || {};
        const p = L.tile_pos_in_workspace_view || [0, 0];
        const size = L.tile_size || [0, 0];
        return { x: p[0] * sx, y: p[1] * sy, w: size[0] * sx, h: size[1] * sy,
                 window: w, focused: !!w.is_focused };
    });
}
