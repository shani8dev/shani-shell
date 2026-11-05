.pragma library
// The handwriting pad's geometry, in plain JS (tests/test_handwriting.py runs it in
// node): which ruled row a stroke belongs to, whether a stroke is a scribble that
// rubs out what is under it, and whether a pen point is ink or a hover.
// A stroke is [{ x, y, p }] (p: pressure, -1 when the device has none).

// a pen that is not pressed reports a little pressure as it hovers (measured in
// the KDE work: hover sat near 0.02, writing 0.3-0.7); below this it is a hover
var HOVER = 0.1;

function isInk(point, isPen) {
    return !isPen || point.p < 0 || point.p >= HOVER;
}

function bounds(stroke) {
    var b = { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity };
    for (var i = 0; i < stroke.length; i++) {
        var p = stroke[i];
        b.x0 = Math.min(b.x0, p.x); b.y0 = Math.min(b.y0, p.y);
        b.x1 = Math.max(b.x1, p.x); b.y1 = Math.max(b.y1, p.y);
    }
    return b;
}

// the row a stroke was written on: where its middle sits, so a descender (g, y)
// reaching into the row below still counts for the row it began on
function rowOf(stroke, rowHeight, rows) {
    var b = bounds(stroke);
    var mid = b.y0 + (b.y1 - b.y0) * 0.35;
    return Math.max(0, Math.min(rows - 1, Math.floor(mid / rowHeight)));
}

// a scribble: going back and forth sideways at least five times, wider than tall
// or about as wide - not an m or a w, which turn three or four times
function isScribble(stroke) {
    if (stroke.length < 8)
        return false;
    var turns = 0, dir = 0, travelled = 0;
    for (var i = 1; i < stroke.length; i++) {
        var dx = stroke[i].x - stroke[i - 1].x;
        travelled += Math.abs(dx);
        if (Math.abs(dx) < 1.5)
            continue;
        var d = dx > 0 ? 1 : -1;
        if (dir !== 0 && d !== dir)
            turns++;
        dir = d;
    }
    var b = bounds(stroke);
    var w = b.x1 - b.x0;
    return turns >= 5 && w > 6 && travelled > w * 3;
}

// what a scribble rubs out: the strokes it covers more than half of
function rubOut(strokes, scribble) {
    var s = bounds(scribble);
    return strokes.filter(function (st) {
        var b = bounds(st);
        var ix = Math.max(0, Math.min(b.x1, s.x1) - Math.max(b.x0, s.x0));
        var iy = Math.max(0, Math.min(b.y1, s.y1) - Math.max(b.y0, s.y0));
        var area = Math.max(1, (b.x1 - b.x0) * (b.y1 - b.y0));
        var cover = (ix * iy) / area;
        // a thin stroke (an i's line, a dash) has no area: its length under the scribble counts
        var thin = (b.x1 - b.x0) < 3 || (b.y1 - b.y0) < 3;
        return !(thin ? ix > 0 && iy >= 0 && b.y0 <= s.y1 && b.y1 >= s.y0 : cover > 0.5);
    });
}

// the rows' strokes, top to bottom, the empty ones left out
function byRow(strokes, rowHeight, rows) {
    var out = [];
    for (var r = 0; r < rows; r++)
        out.push([]);
    for (var i = 0; i < strokes.length; i++)
        out[rowOf(strokes[i], rowHeight, rows)].push(strokes[i]);
    return out;
}
