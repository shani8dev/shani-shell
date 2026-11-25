pragma Singleton

// Your apps as a row: the pinned ones in your order, then whatever else is
// running - one list for every place that shows them (the dock, the bar's
// taskbar, the rail as a launcher), so they cannot disagree.
//
//   Taskbar.items          [{ id, entry, windows, pinned }]
//   Taskbar.activate(it)   start it, bring back its minimised windows, or step
//                          through its windows; true when it was started
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var entryOf: id => DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id)
    readonly property var running: {
        const groups = {};
        for (const w of Object.values(Niri.windows)) {
            const key = (w.app_id || "").toLowerCase();
            (groups[key] = groups[key] || []).push(w);
        }
        return groups;
    }
    readonly property var items: {
        const out = [], seen = {};
        for (const id of Settings.data.dockPinned) {
            const e = root.entryOf(id);
            if (!e || !AppFilter.allowed(e.id))
                continue;
            // its windows by the entry's class, its id, or the id it was pinned as
            // (an entry found by a guess carries another id than the windows do)
            const key = (e.startupClass || e.id).toLowerCase();
            const pinnedAs = String(id).toLowerCase();
            const ws = root.running[key] || root.running[e.id.toLowerCase()] || root.running[pinnedAs] || [];
            seen[key] = seen[e.id.toLowerCase()] = seen[pinnedAs] = true;
            out.push({ id: e.id, entry: e, windows: ws, pinned: true });
        }
        for (const key of Object.keys(root.running)) {
            if (seen[key] || key === "")
                continue;
            out.push({ id: key, entry: root.entryOf(key), windows: root.running[key], pinned: false });
        }
        return out;
    }
    function activate(it) {
        if (it.windows.length === 0) {
            if (it.entry)
                Launch.app(it.entry.id);
            return !!it.entry;
        }
        // an app whose windows are all minimised: bring them back
        const down = it.windows.filter(w => Niri.isMinimised(w));
        if (down.length === it.windows.length) {
            down.forEach(w => Niri.restore(w.id));
            return false;
        }
        const ids = it.windows.filter(w => !Niri.isMinimised(w)).map(w => w.id).sort((a, b) => a - b);
        const cur = ids.indexOf(Niri.focusedWindowId);
        const targetId = ids[cur < 0 ? 0 : (cur + 1) % ids.length];
        const target = Niri.windows[targetId];
        if (target)
            Niri.focusWin(target);
        else
            Niri.action("focus-window", "--id", targetId);
        return false;
    }
}
