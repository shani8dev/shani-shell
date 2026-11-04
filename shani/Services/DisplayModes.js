.pragma library
// The mode a laptop's built-in panel runs on battery: the same resolution, at the
// lowest refresh of 59 Hz or more - only when it has a faster one to step down from.
// "" = leave it as configured. Plain JS, so tests/test_display_modes.py runs it.

function internal(name) {
    return /^(eDP|LVDS|DSI)/.test(name || "");
}

// output: { name, mode: "WxH@R", modes: [{ w, h, r }] }; configured: "WxH@R" or ""
function batteryMode(output, configured) {
    if (!output || !internal(output.name) || !(output.modes || []).length)
        return "";
    const res = (configured || output.mode || "").split("@")[0];
    const same = output.modes.filter(m => m.w + "x" + m.h === res);
    if (!same.some(m => m.r > 61))
        return "";
    const slow = same.filter(m => m.r >= 59).sort((a, b) => a.r - b.r)[0];
    return slow ? slow.w + "x" + slow.h + "@" + slow.r.toFixed(3) : "";
}
