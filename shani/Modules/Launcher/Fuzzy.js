.pragma library
// Typo-tolerant matching for the launcher: "fierfox" finds Firefox, "settngs"
// finds Settings. Only asked when nothing matched exactly, by prefix or inside
// the text, and ranked below all of those.
//
// words(text) is computed once per app or action (when the list changes), so a
// keystroke costs one small edit-distance table per word - no processes.

// the words of a name, lower case: "Shell settings" -> ["shell", "settings"]
function words(text) {
    return String(text || "").toLowerCase().split(/[\s\-_.&/()]+/).filter(w => w.length > 1);
}

// typos allowed for a query this long: none below 4 letters (too many look alike)
function allowed(n) {
    return n < 4 ? 0 : n < 7 ? 1 : 2;
}

// the fewest typos (a letter wrong, missing, extra, or two swapped) between q and
// the start of word w - so "firef" still finds "firefox"
function prefixDistance(q, w) {
    const m = q.length, n = w.length;
    let prev2 = null, prev = new Array(n + 1), cur;
    for (let j = 0; j <= n; j++) prev[j] = j;
    for (let i = 1; i <= m; i++) {
        cur = new Array(n + 1);
        cur[0] = i;
        for (let j = 1; j <= n; j++) {
            const cost = q[i - 1] === w[j - 1] ? 0 : 1;
            let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
            if (i > 1 && j > 1 && q[i - 1] === w[j - 2] && q[i - 2] === w[j - 1])
                v = Math.min(v, prev2[j - 2] + 1);
            cur[j] = v;
        }
        prev2 = prev;
        prev = cur;
    }
    // q against every start of w: the best one
    let best = Infinity;
    for (let j = Math.max(0, m - 2); j <= n; j++) best = Math.min(best, prev[j]);
    return best;
}

// 0 for no match; otherwise 30 (one typo) or 25 (two) - below every exact,
// prefix or substring score the launcher gives. Each word typed must be near a
// word of the name (its first letter right: typos are rarely there).
function score(ws, q) {
    const terms = String(q || "").toLowerCase().split(/\s+/).filter(t => t);
    if (!terms.length || !ws || !ws.length)
        return 0;
    let worst = 0;
    for (const t of terms) {
        const max = allowed(t.length);
        let best = Infinity;
        for (const w of ws) {
            if (w[0] !== t[0])
                continue;
            if (w.startsWith(t)) { best = 0; break; }
            if (max === 0 || Math.abs(w.length - t.length) > max && w.length < t.length)
                continue;
            best = Math.min(best, prefixDistance(t, w));
        }
        if (best > max)
            return 0;
        worst = Math.max(worst, best);
    }
    return worst === 0 ? 0 : 35 - 5 * worst;
}
