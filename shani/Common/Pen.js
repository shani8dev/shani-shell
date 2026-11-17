.pragma library
// A pen on the board (Modules/Whiteboard; docs/FORM-FACTORS.md, the board):
// how wide its line is from how hard it presses, and which touches are a
// resting hand rather than a finger writing. Pure, tested in node
// (tests/test_pen.py).

// pressure 0..1 from a pen: light is thin, hard is thick (0.35x to 1.65x the
// chosen width); the mouse and fingers report no pressure (0) or always 1:
// the chosen width
function width(base, pressure, isPen) {
    if (!isPen || !(pressure > 0))
        return base;
    var p = Math.min(1, pressure);
    return base * (0.35 + 1.3 * p);
}

// a touch is a palm (or a sleeve, a forearm) when its contact is broad: a
// finger's is ~10-20 mm, a resting hand's several times that. maxPx: the
// broadest a finger may be, in the panel's pixels.
function isPalm(diameterW, diameterH, maxPx) {
    return Math.max(diameterW || 0, diameterH || 0) > maxPx;
}

// what the board ignores: every touch while the pen is on the board or just
// above it (the hand holding it rests there), and a palm at any time
function rejectTouch(penNear, diameterW, diameterH, maxPx) {
    return !!penNear || isPalm(diameterW, diameterH, maxPx);
}
