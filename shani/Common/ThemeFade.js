.pragma library
// The light/dark cross-fade, as plain JS so tests/test_theme_fade.py runs it.
// Theme.qml animates `darkT` from 0 (light) to 1 (dark) over ~300 ms when the
// style flips (nothing at all while idle — the animation only runs while it
// moves), and blends every palette token between its light and dark value
// with blendC. Colours are [r, g, b, a] arrays of 0..1, the way QML colours
// read themselves (r/g/b/a). t outside 0..1 is clamped, so a stray value
// can never overshoot into a wild colour.

function clamp01(x) { return Math.min(1, Math.max(0, x)); }

function lerp(a, b, t) { return a + (b - a) * clamp01(t); }

// channels of [r, g, b, a]
function blendC(light, dark, t) {
    const k = clamp01(t);
    return [lerp(light[0], dark[0], k), lerp(light[1], dark[1], k),
            lerp(light[2], dark[2], k), lerp(light[3], dark[3], k)];
}

// how long the fade runs: a gentle 300 ms, or nothing with reduce motion —
// the motion is the point of the setting, so it must not be smuggled back in
function fadeMs(reduceMotion) { return reduceMotion ? 0 : 300; }
