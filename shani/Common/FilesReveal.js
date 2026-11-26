.pragma library
// Show a file's folder in Files with the file chosen. A URL or a relative name
// is not a path on disk, so there is nothing to reveal.
function show(path, files) {
    const p = String(path || "");
    if (!p.startsWith("/")) return false;
    const at = p.lastIndexOf("/");
    files.show(at === 0 ? "/" : p.substring(0, at));
    files.select(p, "single");
    return true;
}
