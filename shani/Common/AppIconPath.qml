pragma Singleton
// One place an app icon name/path is resolved, so every surface falls back the
// same way. `entry` is an icon name/path string, or an object with an .icon.
// Used by AppIcon.qml (visual) and by modules that only need the name/path.
import Quickshell
import QtQuick

QtObject {
    // nameFor: the icon name to show, or `fallback` (a name, "" for none).
    function nameFor(entry, fallback) {
        if (!entry)
            return fallback || "";
        const name = typeof entry === "string" ? entry : entry.icon;
        return name ? name : (fallback || "");
    }
    // pathFor: "" when none, file:// for absolute paths, else icon theme answer.
    // fallback: false for none, true for theme placeholder, or an icon name.
    function pathFor(entry, fallback) {
        if (!entry)
            return "";
        const name = typeof entry === "string" ? entry : entry.icon;
        if (!name)
            return "";
        if (name.startsWith("/"))
            return "file://" + name;
        return Quickshell.iconPath(name, fallback);
    }
}
