.pragma library
// Pure rules for sectioned Speed Dial (libcprime's PinManage / corebox's Speed
// Dial). Kept as plain JS so tests/test_speed_dial.py runs the very same code in
// node, without a QuickShell runtime. SpeedDial.qml owns the JSON file, the
// translations and the opening of paths.
//
// One JSON object in the shell's state folder:
//   { sections: [ { name: "Work", entries: [ { name, path, pinnedAt } ] } ] }
// `pinnedAt` is milliseconds since the epoch; entries show newest first, as
// corebox's loadSpeedDial sorts PinManage's "hh.mm.ss - dd.MM.yyyy" stamps.
// A path is stored once across all sections (PinManage's checkingPinPathEx),
// canonicalised so /a/./b, /a//b and /a/b/ are the same shortcut.

var DEFAULT_SECTION = "Speed Dial";
var MAX_NAME = 60;
var MAX_PATH = 4096;
var MAX_SECTIONS = 12;
var MAX_ENTRIES = 40;
var MAX_PLACES = 18;

// User-entered names become JSON field labels, so no path characters, no
// controls and no key that could shadow Object.prototype.
function cleanName(name) {
    var s = String(name == null ? "" : name).trim();
    if (!s || s.length > MAX_NAME)
        return "";
    if (s.indexOf("..") >= 0 || /[\/\\\u0000-\u001f\u007f]/.test(s))
        return "";
    if (s in Object.prototype)      // __proto__, constructor, toString, …
        return "";
    return s;
}

// Lexical canonical path: expand a leading ~, collapse slashes, drop "." and
// resolve "..", lose the trailing slash. Nothing here touches the filesystem.
function canonical(path, home) {
    var s = String(path == null ? "" : path).trim();
    if (!s || s.length > MAX_PATH)
        return "";
    if (s.charAt(0) === "~" && (s.length === 1 || s.charAt(1) === "/")) {
        var h = String(home == null ? "" : home).replace(/\/+$/, "");
        if (!h)
            return "";
        s = h + s.slice(1);
    }
    var absolute = s.charAt(0) === "/";
    var raw = s.split("/");
    var out = [];
    for (var i = 0; i < raw.length; i++) {
        var p = raw[i];
        if (!p || p === ".")
            continue;
        if (p === "..") {
            if (out.length && out[out.length - 1] !== "..")
                out.pop();
            else if (!absolute)
                out.push("..");
            continue;
        }
        out.push(p);
    }
    var joined = out.join("/");
    return absolute ? "/" + joined : joined;
}

function _time(value) {
    var t = Number(value);
    return isFinite(t) && t > 0 ? t : 0;
}

function sectionIndex(data, name) {
    var d = normalise(data);
    var n = cleanName(name).toLowerCase();
    for (var i = 0; i < d.sections.length; i++)
        if (d.sections[i].name.toLowerCase() === n)
            return i;
    return -1;
}

// Read a hand-edited file defensively: a bad section or entry is dropped, never
// allowed to break the whole list. Duplicate names (case-insensitive) and
// duplicate canonical paths (across every section) keep their first occurrence.
function normalise(data, home) {
    var out = { sections: [] };
    if (!data || typeof data !== "object" || Array.isArray(data))
        return out;
    var rawSections = Array.isArray(data.sections) ? data.sections : [];
    var seenPaths = {};
    var seenSections = {};
    for (var i = 0; i < rawSections.length && out.sections.length < MAX_SECTIONS; i++) {
        var raw = rawSections[i];
        if (!raw || typeof raw !== "object")
            continue;
        var name = cleanName(raw.name);
        if (!name || seenSections["#" + name.toLowerCase()])
            continue;
        seenSections["#" + name.toLowerCase()] = true;
        var section = { name: name, entries: [] };
        var seenNames = {};
        var rawEntries = Array.isArray(raw.entries) ? raw.entries : [];
        for (var j = 0; j < rawEntries.length && section.entries.length < MAX_ENTRIES; j++) {
            var e = rawEntries[j];
            if (!e || typeof e !== "object")
                continue;
            var entryName = cleanName(e.name);
            var path = canonical(e.path, home);
            var key = entryName.toLowerCase();
            if (!entryName || !path || seenNames["#" + key] || seenPaths["#" + path])
                continue;
            seenNames["#" + key] = true;
            seenPaths["#" + path] = true;
            section.entries.push({ name: entryName, path: path, pinnedAt: _time(e.pinnedAt) });
        }
        out.sections.push(section);
    }
    return out;
}

// libcprime makes a "Speed Dial" section when the settings file has none.
function seed(data, home) {
    var out = normalise(data, home);
    if (!out.sections.length)
        out.sections.push({ name: DEFAULT_SECTION, entries: [] });
    return out;
}

function sections(data) {
    return normalise(data).sections.map(function (s) {
        return { name: s.name, count: s.entries.length };
    });
}

// Newest first, then by name so equal timestamps stay stable.
function entries(data, name) {
    var d = normalise(data);
    var i = sectionIndex(d, name);
    if (i < 0)
        return [];
    return d.sections[i].entries.slice().sort(function (a, b) {
        return b.pinnedAt - a.pinnedAt || a.name.localeCompare(b.name);
    });
}

// One flat list for the launcher and the dock menu. normalise() has already
// dropped duplicate canonical paths, so every place appears once even when a
// hand-edited file pins the same folder in two sections.
function places(data, home, limit) {
    var d = normalise(data, home);
    var out = [];
    for (var i = 0; i < d.sections.length; i++) {
        var section = d.sections[i];
        for (var j = 0; j < section.entries.length; j++) {
            var e = section.entries[j];
            out.push({ name: e.name, section: section.name, path: e.path, pinnedAt: e.pinnedAt });
        }
    }
    out.sort(function (a, b) {
        return b.pinnedAt - a.pinnedAt || a.name.localeCompare(b.name);
    });
    var n = typeof limit === "number" && limit > 0 ? limit : MAX_PLACES;
    return out.slice(0, n);
}

// Where a path is already pinned, for a useful duplicate error.
function findPath(data, path, home) {
    var d = normalise(data, home);
    var p = canonical(path, home);
    if (!p)
        return null;
    for (var i = 0; i < d.sections.length; i++) {
        for (var j = 0; j < d.sections[i].entries.length; j++) {
            if (d.sections[i].entries[j].path === p)
                return { section: d.sections[i].name, name: d.sections[i].entries[j].name };
        }
    }
    return null;
}

// Every mutator returns the whole new document, or null for a refusal: invalid
// input, a duplicate, a missing target or a cap. The QML service owns the
// user-facing reason; no mutator writes anything until commit() in QML.
function addSection(data, name) {
    var n = cleanName(name);
    if (!n)
        return null;
    var out = normalise(data);
    if (sectionIndex(out, n) >= 0 || out.sections.length >= MAX_SECTIONS)
        return null;
    out.sections.push({ name: n, entries: [] });
    return out;
}

function renameSection(data, oldName, newName) {
    var n = cleanName(newName);
    var out = normalise(data);
    var i = sectionIndex(out, oldName);
    var j = sectionIndex(out, newName);
    if (!n || i < 0 || (j >= 0 && j !== i))
        return null;
    out.sections[i].name = n;
    return out;
}

function removeSection(data, name) {
    var out = normalise(data);
    var i = sectionIndex(out, name);
    if (i < 0)
        return null;
    out.sections.splice(i, 1);
    return out;
}

function addEntry(data, sectionName, name, path, now, home) {
    var n = cleanName(name);
    var p = canonical(path, home);
    var out = normalise(data, home);
    var i = sectionIndex(out, sectionName);
    if (!n || !p || i < 0 || out.sections[i].entries.length >= MAX_ENTRIES)
        return null;
    var entries = out.sections[i].entries;
    for (var j = 0; j < entries.length; j++)
        if (entries[j].name.toLowerCase() === n.toLowerCase())
            return null;
    if (findPath(out, p, home))
        return null;
    entries.push({ name: n, path: p, pinnedAt: _time(now) });
    return out;
}

function removeEntry(data, sectionName, name) {
    var out = normalise(data);
    var i = sectionIndex(out, sectionName);
    if (i < 0)
        return null;
    var entries = out.sections[i].entries;
    for (var j = 0; j < entries.length; j++) {
        if (entries[j].name.toLowerCase() === cleanName(name).toLowerCase()) {
            entries.splice(j, 1);
            return out;
        }
    }
    return null;
}

// A rename keeps the path and the pin time, so its place in the list is stable.
function renameEntry(data, sectionName, oldName, newName) {
    var n = cleanName(newName);
    var out = normalise(data);
    var i = sectionIndex(out, sectionName);
    if (!n || i < 0)
        return null;
    var entries = out.sections[i].entries;
    var target = null;
    for (var j = 0; j < entries.length; j++) {
        if (entries[j].name.toLowerCase() === cleanName(oldName).toLowerCase())
            target = entries[j];
        if (entries[j].name.toLowerCase() === n.toLowerCase() && entries[j] !== target)
            return null;
    }
    if (!target)
        return null;
    target.name = n;
    return out;
}
