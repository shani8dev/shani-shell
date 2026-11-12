.pragma library

// Shape: the corner-radius scale. One table of tokens (xxs … xxl) and the
// arithmetic to turn them into a radius, so a card, a button and a chip are
// cut from the same shape instead of each picking its own number.
//
// The table holds the shell's own radii: s = 10 (the small one), l = 16 (the
// cards), xl = 22 (the large one). `scaleForStrength` turns a 0-100
// "roundness" into a multiplier on that table, so the whole scale moves
// together when a person asks for rounder or squarer corners.

var corners = {
    xxs: 2,
    xs: 8,
    s: 10,
    m: 12,
    l: 16,
    lIncreased: 20,
    xl: 22,
    xlIncreased: 28,
    xxl: 40
};
var maxFixedRadius = 32;

// 0-100, rounded; anything else is the middle
function normalizeStrength(value) {
    if (typeof value !== "number" || !isFinite(value))
        return 50;
    return Math.round(Math.max(0, Math.min(100, value)));
}

function normalizeFixedRadius(value) {
    if (typeof value !== "number" || !isFinite(value))
        return corners.l;
    return Math.round(Math.max(0, Math.min(maxFixedRadius, value)));
}

// the strength a radius stands for (the roundness setting's own value)
function strengthFromRadius(radius) {
    if (typeof radius !== "number" || !isFinite(radius))
        return 50;
    return normalizeStrength(radius * 50 / corners.m);
}

function scaleForStrength(strength) {
    return normalizeStrength(strength) / 50;
}

// the radius of a token; `fixed` (a number) wins over the scale
function radius(token, scale, fixed) {
    if (fixed >= 0)
        return fixed;
    return Math.round(corners[token] * scale);
}

// A corner joined to a larger one keeps its proportion to m under a fixed
// radius, so grouped rows and segmented buttons stay one surface.
function innerRadius(token, scale, fixed) {
    if (fixed >= 0)
        return Math.round(Math.min(fixed, corners[token] * fixed / corners.m));
    return radius(token, scale, fixed);
}

function scaledRadius(radius, limit, scale, fixed) {
    if (fixed >= 0)
        return Math.max(0, Math.min(limit, fixed));
    return Math.max(0, Math.min(limit, radius * scale));
}

// the radius of a circle or a pill: half of the smaller side
function fullRadius(width, height, scale, fixed) {
    const half = Math.max(0, Math.min(width, height)) / 2;
    if (fixed >= 0)
        return Math.min(half, fixed);
    return half * Math.min(1, scale);
}

// a button's corner: round when it is a pill, squared when it is pressed
function buttonRadius(width, height, sizeHeight, pressed, round, scale, fixed, morph = true, pill = true) {
    if (!pill)
        return radius("l", scale, fixed);
    const morphed = pressed && morph;
    if (!morphed && round)
        return fullRadius(width, height, scale, fixed);
    return radius(buttonCorner(sizeHeight, morphed), scale, fixed);
}

function buttonCorner(sizeHeight, pressed) {
    if (sizeHeight <= 40)
        return pressed ? "s" : "m";
    if (sizeHeight <= 56)
        return pressed ? "m" : "l";
    return pressed ? "l" : "xl";
}
