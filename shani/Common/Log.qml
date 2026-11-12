pragma Singleton
// Log: the shell's own log line, with a name on it.
//
// The shell runs for days, so when something goes wrong the log is the only
// account of it. `Log.scoped("Files")` gives a logger that says where a
// line came from, and the level can be raised for one name while the rest
// stay quiet:
//
//   SHANI_LOG=Files,Audio   only these two names
//   SHANI_LOG=*             everything
//   SHANI_LOG=Files:debug   this one name, and its debug lines too
//
// Without SHANI_LOG only warnings and errors are written, so the shell does
// not fill the log with noise. Nothing here throws: a logger that breaks the
// thing it is watching is worse than no logger.
import Quickshell
import QtQuick

Singleton {
    id: root

    // "Files" | "Files,Audio" | "Files:debug" | "*" | ""
    readonly property string filter: Quickshell.env("SHANI_LOG") || ""
    readonly property bool all: root.filter === "*"

    function wants(name, level) {
        if (root.all)
            return true;
        const parts = root.filter.split(",").map(p => p.trim()).filter(p => p !== "");
        const named = parts.some(p => p === name || p.split(":")[0] === name);
        if (level === "debug")
            return named && parts.some(p => p === name + ":debug");
        if (level === "info")
            return named;
        // warnings and errors are on by default: they are the ones that explain
        // what went wrong, and they are rare
        return named || parts.length === 0;
    }

    function write(name, level, args) {
        if (!root.wants(name, level))
            return;
        const parts = [];
        for (const a of args)
            parts.push(typeof a === "string" ? a : JSON.stringify(a));
        console.log("[" + name + "] " + parts.join(" "));
    }

    // a logger bound to one name: log.warn("…"), log.info("…"), log.debug("…")
    function scoped(name) {
        return {
            "debug": function () { root.write(name, "debug", Array.prototype.slice.call(arguments)); },
            "info": function () { root.write(name, "info", Array.prototype.slice.call(arguments)); },
            "warn": function () { root.write(name, "warn", Array.prototype.slice.call(arguments)); },
            "error": function () { root.write(name, "error", Array.prototype.slice.call(arguments)); }
        };
    }
}
