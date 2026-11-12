.pragma library
// The file manager's search: what is typed in the search box is matched
// against the names in the folder. A plain word matches anywhere in a name
// ("port" finds "report.png"); with * or ? in it, it is a pattern ("*.png",
// "photo?.jpg").

function isPattern(query) {
    return query.indexOf("*") >= 0 || query.indexOf("?") >= 0;
}

// the longest piece of a pattern that must appear: "a*b" must contain "a"
function needle(query) {
    if (!isPattern(query))
        return query;
    return query.split(/[*?]+/).reduce((longest, part) => part.length > longest.length ? part : longest, "");
}

// * and ? against a name, the way a shell does it
function wildcard(name, pattern) {
    let at = 0;
    let p = 0;
    let star = -1;
    let mark = 0;
    while (at < name.length) {
        if (p < pattern.length && (pattern[p] === "?" || pattern[p] === name[at])) {
            at++;
            p++;
            continue;
        }
        if (p < pattern.length && pattern[p] === "*") {
            star = p++;
            mark = at;
            continue;
        }
        if (star < 0)
            return false;
        p = star + 1;
        at = ++mark;
    }
    while (p < pattern.length && pattern[p] === "*")
        p++;
    return p === pattern.length;
}

// a matcher, made once per keystroke and used for every name
function compile(query) {
    const folded = String(query || "").toLowerCase();
    if (folded === "")
        return { "test": () => true };
    if (!isPattern(folded))
        return { "test": name => String(name).toLowerCase().indexOf(folded) >= 0 };
    return { "test": name => wildcard(String(name).toLowerCase(), folded) };
}

function matches(matcher, entry) {
    if (!matcher)
        return true;
    return matcher.test(entry.name || "");
}
