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
    // the file is external input: a stray markup token would reach the
    // notification title, where the daemon reads it as Pango markup
    const token = t.split(/\s+/)[0];
    return /^[A-Za-z0-9._+-]+$/.test(token) ? token : "";
}

// Numeric part only: a rollback must not be announced as "what's new".
function compareVersions(a, b) {
    const pa = String(a).split("."), pb = String(b).split(".");
    for (let i = 0; i < 3; i++) {
        const na = parseInt(pa[i], 10) || 0, nb = parseInt(pb[i], 10) || 0;
        if (na !== nb)
            return na < nb ? -1 : 1;
    }
    return 0;
}

// current: /etc/shani-version now; lastSeen: what state remembers.
// Returns "show" (new version, tell them), "record" (first sighting, store
// it without telling) or "none" (already told, nothing installed, or a rollback).
function shouldShow(current, lastSeen) {
    if (!current)
        return "none";
    if (!lastSeen)
        return "record";
    if (compareVersions(current, lastSeen) < 0)
        return "none";
    return current !== lastSeen ? "show" : "none";
}
