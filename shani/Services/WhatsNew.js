.pragma library
// "What's new" after an update, as plain JS so tests/test_whatsnew.py runs it.
// The installed version lives in /etc/shani-version; the last version this
// shell has told the person about lives in Quickshell state. Told once per
// version: a version never seen before is shown (and then recorded), the
// version already recorded is never told again, and a first install (nothing
// recorded yet) is recorded silently — a new computer is not an update.

function parseVersion(text) {
    const t = String(text || "").trim();
    if (!t)
        return "";
    const m = t.match(/\d+\.\d+(?:\.\d+)?(?:-[\w.]+)?/);
    if (m)
        return m[0];
    return t.split(/\s+/)[0];
}

// current: /etc/shani-version now; lastSeen: what state remembers.
// Returns "show" (new version, tell them), "record" (first sighting, store
// it without telling) or "none" (already told, or nothing installed).
function shouldShow(current, lastSeen) {
    if (!current)
        return "none";
    if (!lastSeen)
        return "record";
    return current !== lastSeen ? "show" : "none";
}
