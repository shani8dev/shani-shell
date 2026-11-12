.pragma library

// WheelInput: telling a wheel from a touchpad.
//
// Qt sends scroll phases only for the finger axis source; pixelDelta also
// comes with wheels from Qt 6.12. A wheel reports angleDelta (120 per notch),
// a touchpad reports pixelDelta (a few pixels per finger movement). A slider
// that treats both the same jumps a whole step for every pixel of a finger
// slide - the touchpad must move by pixels, the wheel by notches.
//
// The kinds: none, touchpad, wheel (a whole notch), highResWheel (a fraction
// of a notch).

const Kind = Object.freeze({
    none: "none",
    touchpad: "touchpad",
    wheel: "wheel",
    highResWheel: "highResWheel"
});

function isTouchpad(wheel) {
    if (wheel.phase === Qt.NoScrollPhase)
        return false;
    return wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0;
}

function verticalKind(wheel) {
    return axisKind(wheel, wheel.angleDelta.y);
}

function axisKind(wheel, angle) {
    if (isTouchpad(wheel))
        return Kind.touchpad;
    if (angle === 0)
        return Kind.none;
    return angle % 120 === 0 ? Kind.wheel : Kind.highResWheel;
}

// the delta to act on: pixels for a finger, angles for a wheel
function anyAxisDelta(wheel) {
    const point = isTouchpad(wheel) ? wheel.pixelDelta : wheel.angleDelta;
    return point.x || point.y;
}

function isHorizontal(wheel) {
    if (wheel.modifiers & Qt.ShiftModifier)
        return true;
    return Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
}

function dominantDelta(point) {
    return Math.abs(point.x) > Math.abs(point.y) ? point.x : point.y;
}

// How much a wheel event should move a control: one notch moves it by
// `notchStep`, and a finger moves it by its own pixels - `pixelsPerStep`
// pixels are one step - so a slide over a slider is smooth and a notch is a
// whole step. The result is clamped to one step either way: a fast flick
// must not jump the value across the range.
function stepDelta(wheel, notchStep, pixelsPerStep) {
    const step = notchStep === undefined ? 1 : notchStep;
    if (isTouchpad(wheel)) {
        const pixels = dominantDelta(wheel.pixelDelta);
        const steps = pixels / (pixelsPerStep || 120);
        return Math.max(-1, Math.min(1, steps)) * step;
    }
    const angle = wheel.angleDelta.y;
    if (angle === 0)
        return 0;
    const notches = angle / 120;
    return Math.max(-1, Math.min(1, notches)) * step;
}
