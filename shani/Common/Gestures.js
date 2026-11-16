.pragma library
// Edge swipes on a touch screen (docs/FORM-FACTORS.md, the tablet): which
// swipe a finger made from an edge, by how far it came in and how straight.
// Pure, run in node by tests/test_gestures.py.
//
//   from the bottom -> the launcher       from the top   -> Quick Settings
//   from the left   -> back               from the right -> the overview

var ACTIONS = { bottom: "launcher", top: "quick-settings", left: "back", right: "overview" };

// edge: where the finger went down; dx, dy: how far it moved (screen pixels,
// y down); min: how far in counts as a swipe (a tap or a short slip is not one)
function classify(edge, dx, dy, min) {
    var inward = { bottom: -dy, top: dy, left: dx, right: -dx }[edge];
    var across = (edge === "top" || edge === "bottom") ? Math.abs(dx) : Math.abs(dy);
    if (inward === undefined || !(inward >= min) || across > inward * 0.75)
        return "";
    return ACTIONS[edge];
}

// A finger has no right button. A long press asks for what the right button
// asks for, and the click that follows on release must not fire as well - the
// menu would open and the item under the finger would open too. One state per
// item, in the QML that owns it:
//
//   property var held: Hold.state()
//   onPressed: Hold.press(held)
//   onPressAndHold: Hold.hold(held)          // then what the right button does
//   onClicked: if (Hold.swallowed(held)) return; ...
function state() {
    return { long: false };
}

function press(s) {
    if (s)
        s.long = false;
}

function hold(s) {
    if (s)
        s.long = true;
}

// true (once) when this click is the end of a long press: swallow it
function swallowed(s) {
    if (!s || !s.long)
        return false;
    s.long = false;
    return true;
}

// A pinch on something that zooms in whole steps (the map's levels): one step
// each time the fingers double (or halve) the distance since the last step.
// scale: the pinch so far (1 at the start); base: the scale at the last step.
// Returns { steps: +1 / -1 / 0, base: the new base }.
function pinchSteps(scale, base) {
    if (!(scale > 0) || !(base > 0))
        return { steps: 0, base: base > 0 ? base : 1 };
    var r = Math.log(scale / base) / Math.LN2;
    if (r >= 1)
        return { steps: 1, base: base * 2 };
    if (r <= -1)
        return { steps: -1, base: base / 2 };
    return { steps: 0, base: base };
}
