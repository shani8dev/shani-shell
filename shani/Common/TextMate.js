.pragma library
// TextMate grammar highlighter. Takes a normalized grammar (from bridge/textmate.py)
// and a theme ([{ scope, foreground }]) and turns plain text into HTML spans.
// Supports `match` patterns with captures, and `begin`/`end` blocks. Includes
// are resolved against the grammar's repository. This is a pragmatic subset —
// enough to colour real .tmLanguage grammars, not a full Oniguruma engine.

function escapeHtml(s) {
    return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// Pick the theme foreground for a TextMate scope. Themes list scopes from
// most-specific to least; the longest scope that is a prefix of `scope` wins.
function colorFor(scope, theme) {
    if (!scope || !theme || !theme.length) return "";
    let best = "", bestLen = -1;
    for (const entry of theme) {
        const scopes = String(entry.scope || "").split(/[\s,]+/).filter(Boolean);
        for (const s of scopes) {
            if (scope === s || scope.indexOf(s + ".") === 0 || s.indexOf(scope + ".") === 0) {
                if (s.length > bestLen) { bestLen = s.length; best = entry.foreground || ""; }
            }
        }
    }
    return best;
}

// Build a list of { from, to, scope } spans by applying a pattern's regex.
function collect(text, pattern, grammar, out, depth) {
    if (depth > 8 || !pattern) return;
    const regexStr = pattern.match || pattern.begin;
    if (!regexStr) {
        if (pattern.patterns) for (const p of pattern.patterns) collect(text, p, grammar, out, depth + 1);
        return;
    }
    let re;
    try { re = new RegExp(regexStr, "gm"); } catch (e) { return; }
    let m;
    let guard = 0;
    while ((m = re.exec(text)) !== null && guard++ < 20000) {
        if (m[0].length === 0) { re.lastIndex++; continue; }
        const start = m.index, end = start + m[0].length;
        const name = pattern.name || "";
        if (name) out.push({ from: start, to: end, scope: name });
        // captures (group number -> scope)
        const caps = pattern.captures || (pattern.begin ? pattern.beginCaptures : null);
        if (caps) {
            for (let g = 1; g < m.length; g++) {
                const c = caps[String(g)];
                if (c && c.name && m[g]) {
                    const gs = text.indexOf(m[g], start);
                    if (gs >= 0) out.push({ from: gs, to: gs + m[g].length, scope: c.name });
                }
            }
        }
        // nested patterns inside the matched begin..end region
        if (pattern.patterns && pattern.begin && pattern.end) {
            const region = text.substring(start, end);
            const sub = [];
            for (const p of pattern.patterns) collect(region, p, grammar, sub, depth + 1);
            for (const s of sub) out.push({ from: start + s.from, to: start + s.to, scope: s.scope });
        }
    }
    // resolve includes
    if (pattern.patterns) {
        for (const p of pattern.patterns) {
            if (p.include && grammar.repository) {
                const key = String(p.include).replace(/^#/, "").split(".")[0];
                collect(text, grammar.repository[key], grammar, out, depth + 1);
            } else if (!p.match && !p.begin) {
                collect(text, p, grammar, out, depth + 1);
            }
        }
    }
}

// Return HTML with <span style="color:#..."> for each coloured span.
function highlight(text, grammar, theme) {
    if (!text) return "";
    if (!grammar || !grammar.patterns || !grammar.patterns.length)
        return escapeHtml(text);
    const spans = [];
    for (const p of grammar.patterns) collect(text, p, grammar, spans, 0);
    // sort by start, then by length (innermost first so outer wins on equal start)
    spans.sort((a, b) => a.from - b.from || (b.to - b.from) - (a.to - a.from));

    // Resolve overlaps: keep spans that aren't fully inside an earlier span.
    const kept = [];
    let lastEnd = -1;
    for (const s of spans) {
        if (s.from < lastEnd && s.to <= lastEnd) continue;
        kept.push(s);
        lastEnd = Math.max(lastEnd, s.to);
    }

    let html = "", pos = 0;
    for (const s of kept) {
        if (s.from < pos || s.to > text.length) continue;
        html += escapeHtml(text.substring(pos, s.from));
        const color = colorFor(s.scope, theme);
        const chunk = escapeHtml(text.substring(s.from, s.to));
        html += color ? ('<span style="color:' + color + '">' + chunk + "</span>") : chunk;
        pos = s.to;
    }
    html += escapeHtml(text.substring(pos));
    return html;
}

// Pick a grammar for a file extension from a list of { name, fileTypes, path }.
function grammarFor(ext, grammars) {
    if (!ext || !grammars) return null;
    const e = String(ext).toLowerCase().replace(/^\./, "");
    for (const g of grammars) {
        if ((g.fileTypes || []).some(t => String(t).toLowerCase() === e)) return g;
    }
    return null;
}
