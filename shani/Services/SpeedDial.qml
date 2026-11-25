pragma Singleton
// Speed Dial: named shortcuts to folders and files, grouped into sections
// (libcprime's PinManage and corebox's Speed Dial). GTK bookmarks in Files are
// flat and shared with other apps; these are the shell's own, with a name, a
// section and a pin time, newest first. One JSON file in Quickshell's state
// folder, like Sessions and the parked Shelf; the pure rules are in SpeedDial.js
// so the tests run the very same code without a QuickShell runtime.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "SpeedDial.js" as Logic

Singleton {
    id: root
    property var data: ({ sections: [] })       // { sections: [ { name, entries: [ { name, path, pinnedAt } ] } ] }
    property string error: ""

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string storePath: Quickshell.statePath("speed-dial.json")

    FileView {
        id: store
        path: root.storePath
        printErrors: false                      // nothing pinned yet: no file, no noise
        onLoaded: {
            try { root.data = Logic.seed(JSON.parse(text()), root.home); }
            catch (e) { root.data = Logic.seed(null); }
        }
        onLoadFailed: root.data = Logic.seed(null)
    }

    function clearError() { root.error = ""; }
    function commit(next, message) {
        if (!next) {
            root.error = message;
            return false;
        }
        root.data = next;
        store.setText(JSON.stringify(next));
        root.error = "";
        return true;
    }

    // ---- what the panel shows ---------------------------------------------------
    function sections() { return Logic.sections(root.data); }
    function entries(section) { return Logic.entries(root.data, section); }
    // read-only, flat newest-first places for launcher actions and dock menus
    function places() { return Logic.places(root.data, root.home); }
    function hasSection(name) { return Logic.sectionIndex(root.data, name) >= 0; }
    function count() { return Logic.sections(root.data).reduce((n, s) => n + s.count, 0); }
    function canonical(path) { return Logic.canonical(path, root.home); }

    function _duplicatePath(path) {
        const at = Logic.findPath(root.data, path, root.home);
        if (!at) return "";
        return Tr.t("Already in %1 as %2", at.section, at.name);
    }
    function _badName(what) {
        return Tr.t("Use a %1 name of 1 to 60 characters, without / or \\", what);
    }

    // ---- sections ---------------------------------------------------------------
    function addSection(name) {
        const why = Logic.cleanName(name) && root.hasSection(name)
                    ? Tr.t("That section already exists") : _badName(Tr.t("section"));
        return commit(Logic.addSection(root.data, name), why);
    }

    function renameSection(section, name) {
        return commit(Logic.renameSection(root.data, section, name),
                      Logic.cleanName(name) ? Tr.t("That section already exists") : _badName(Tr.t("section")));
    }

    function removeSection(section) {
        return commit(Logic.removeSection(root.data, section), Tr.t("No section called %1", section));
    }

    // ---- entries ----------------------------------------------------------------
    function addEntry(section, name, path) {
        let why = _badName(Tr.t("shortcut")) + " · " + Tr.t("check the folder and the name");
        if (Logic.cleanName(name) && !Logic.canonical(path, root.home)) why = Tr.t("Type a path");
        else if (Logic.cleanName(name) && !root.hasSection(section)) why = Tr.t("No section called %1", section);
        else if (Logic.cleanName(name) && _duplicatePath(path)) why = _duplicatePath(path);
        return commit(Logic.addEntry(root.data, section, name, path, Date.now(), root.home), why);
    }

    function removeEntry(section, name) {
        return commit(Logic.removeEntry(root.data, section, name), Tr.t("No shortcut called %1", name));
    }

    function renameEntry(section, name, newName) {
        return commit(Logic.renameEntry(root.data, section, name, newName),
                      Logic.cleanName(newName) ? Tr.t("That name is already in this section") : _badName(Tr.t("shortcut")));
    }

    // ---- opening ----------------------------------------------------------------
    // A folder goes to the shell's own file manager; a file goes to the app
    // registered for it. The probe is the one Sessions uses: a flat shortcut
    // does not say whether its path is a directory.
    function open(path) {
        const p = Logic.canonical(path, root.home);
        if (!p) {
            root.error = Tr.t("That shortcut has no path");
            return false;
        }
        root.error = "";
        probe.path = p;
        probe.command = ["sh", "-c", '[ -d "$1" ] && echo dir || echo file', "sh", p];
        probe.running = true;
        return true;
    }

    Process {
        id: probe
        property string path: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const p = probe.path;
                if (text.trim() === "dir") Files.show(p);
                else Quickshell.execDetached(["xdg-open", p]);
            }
        }
    }
}
