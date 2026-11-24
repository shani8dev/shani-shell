.pragma library
// Pure rules for named sessions (apps + documents). Kept as plain JS so
// tests/test_sessions_service.py runs the very same code in node, without a
// QuickShell runtime. The shell's Sessions.qml owns the file and the launchers.
//
// A session is one key in a JSON object: name -> { apps, paths, savedAt }.
// Names are user-entered, so they are cleaned before they touch that object:
// no path characters (the file is one flat object, not a folder of files),
// no controls, and no key that would shadow Object.prototype.

var MAX_NAME = 60;
var MAX_SESSIONS = 24;
var MAX_ITEMS = 100;

function cleanName(name) {
    const s = String(name == null ? "" : name).trim();
    if (!s || s.length > MAX_NAME)
        return "";
    if (s.indexOf("..") >= 0 || /[\/\\\u0000-\u001f\u007f]/.test(s))
        return "";
    if (s in Object.prototype)          // __proto__, constructor, toString, …
        return "";
    return s;
}

// Trim, drop empties and duplicates, keep the first N. Paths and desktop ids
// are plain strings; nothing here opens or resolves them.
function capped(list, limit) {
    const out = [];
    for (const v of Array.isArray(list) ? list : []) {
        const s = String(v == null ? "" : v).trim();
        if (s && out.indexOf(s) < 0)
            out.push(s);
    }
    return out.slice(0, limit || MAX_ITEMS);
}

// Read a hand-edited sessions.json defensively: a bad entry is dropped, not
// allowed to break the whole list or poison the object the shell writes back.
function normalise(data) {
    const out = {};
    if (!data || typeof data !== "object" || Array.isArray(data))
        return out;
    for (const raw of Object.keys(data)) {
        const name = cleanName(raw);
        const s = data[raw];
        if (!name || Object.prototype.hasOwnProperty.call(out, name) || !s || typeof s !== "object")
            continue;
        out[name] = {
            apps: capped(s.apps, MAX_ITEMS),
            paths: capped(s.paths, MAX_ITEMS),
            savedAt: typeof s.savedAt === "string" && s.savedAt ? s.savedAt : ""
        };
        if (Object.keys(out).length >= MAX_SESSIONS)
            break;
    }
    return out;
}

// Newest first, with counts, for the settings page's list.
function toList(data) {
    const d = normalise(data);
    return Object.keys(d).map(function (name) {
        return { name: name, apps: d[name].apps, paths: d[name].paths, savedAt: d[name].savedAt };
    }).sort(function (a, b) {
        return String(b.savedAt).localeCompare(String(a.savedAt)) || a.name.localeCompare(b.name);
    });
}

// Overwrite a name (saving it again is an edit, not a second copy). The oldest
// session goes when the cap is reached. Returns null for an invalid name.
function put(data, name, apps, paths, savedAt) {
    const n = cleanName(name);
    if (!n)
        return null;
    const out = normalise(data);
    delete out[n];
    out[n] = { apps: capped(apps, MAX_ITEMS), paths: capped(paths, MAX_ITEMS), savedAt: String(savedAt || "") };
    const names = Object.keys(out);
    if (names.length > MAX_SESSIONS) {
        names.sort(function (a, b) {
            return String(out[b].savedAt).localeCompare(String(out[a].savedAt)) || a.name.localeCompare(b.name);
        });
        for (const old of names.slice(MAX_SESSIONS))
            delete out[old];
    }
    return out;
}

function drop(data, name) {
    const out = normalise(data);
    const n = cleanName(name);
    if (n)
        delete out[n];
    return out;
}
