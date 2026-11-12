.pragma library
// Paths, the way the file manager needs them: absolute, without a trailing
// slash, with "~" standing for home. The shell's own paths come from the
// backend already absolute, so normalize only tidies what a person typed.

function expandTilde(path, home) {
    if (path === "~")
        return home;
    if (path.indexOf("~/") === 0)
        return home + path.substring(1);
    return path;
}

// "" when the path is not absolute: nothing sensible can be made of it
function normalize(path, home) {
    // the files opened lately (bridge/files.py lists them): a place, not a folder
    if (String(path || "").trim() === "recent:")
        return "recent:";
    const absolute = expandTilde(String(path || "").trim(), home);
    if (absolute === "" || absolute.charAt(0) !== "/")
        return "";
    const parts = [];
    for (const part of absolute.split("/")) {
        if (part === "" || part === ".")
            continue;
        if (part === "..") {
            parts.pop();
            continue;
        }
        parts.push(part);
    }
    return "/" + parts.join("/");
}

// the folder above; "" at the root, "/" for a direct child of it
function parentOf(path) {
    if (!path || path === "/")
        return "";
    const cut = path.lastIndexOf("/");
    return cut <= 0 ? "/" : path.substring(0, cut);
}

function baseName(path) {
    return String(path || "").substring(String(path || "").lastIndexOf("/") + 1);
}

function join(directory, name) {
    if (!directory)
        return "/" + name;
    return directory === "/" ? "/" + name : directory + "/" + name;
}

// "~/Pictures/a.png" for a path under home, so it reads short
function shorten(path, home) {
    if (!home || !path || path.indexOf(home) !== 0)
        return path;
    if (path === home)
        return "~";
    return "~" + path.substring(home.length);
}

function fileUrl(path) {
    if (!path)
        return "";
    return "file://" + path.split("/").map(encodeURIComponent).join("/");
}

function fromUrl(value) {
    const text = String(value || "");
    if (text.indexOf("file://") !== 0)
        return text;
    try {
        return decodeURIComponent(text.substring(7));
    } catch (e) {
        return text.substring(7);
    }
}

// a name that can be given to a file: not empty, not "." or "..", no slash
function validName(name) {
    const trimmed = String(name || "").trim();
    return trimmed !== "" && trimmed !== "." && trimmed !== ".." && trimmed.indexOf("/") < 0;
}
