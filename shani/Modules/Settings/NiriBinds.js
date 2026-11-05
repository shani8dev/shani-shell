.pragma library
// The binds niri really has, read from its config the way niri's own hotkey
// overlay names them. Plain JS, so tests/test_niri_binds.py runs it in node
// against the configs the session and the package ship.

// one line per bind: `Mod+Q repeat=false { close-window; }`, a title when given
function parse(text) {
    const out = [];
    const inBinds = text.slice(text.indexOf("binds {"));
    for (const line of inBinds.split("\n")) {
        const m = /^\s+([A-Za-z0-9+_]+)((?:\s+[a-z-]+=(?:true|false|"[^"]*"|[0-9.]+))*)\s*\{\s*([^;}]+)/.exec(line);
        if (!m)
            continue;
        const t = /hotkey-overlay-title="([^"]*)"/.exec(m[2]);
        if (t && t[1] === "")
            continue;               // niri's own way to hide one
        let title = t ? t[1] : m[3].trim();
        if (!t) {
            if (/^spawn/.test(title))
                continue;           // a command without a name says nothing to a person
            title = title.replace(/\s.*$/, "").replace(/-/g, " ");
            title = title.charAt(0).toUpperCase() + title.slice(1);
        }
        out.push({ key: m[1], title: title });
    }
    return out;
}
