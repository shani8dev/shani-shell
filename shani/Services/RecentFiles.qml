pragma Singleton

// The files the person opened lately, newest first: the desktop's shared
// recently-used.xbel (GTK and most apps write it; GTK appends, so file order is
// oldest first). One reader for the whole shell: the launcher and the overview
// search used to parse it separately, and the overview's copy lost the sort and
// showed the ten oldest files.
//
//   RecentFiles.files   [{ path, name, when, app }], newest first, at most 40
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property int limit: 40
    property var files: []

    /// Parse recently-used.xbel text into [{ path, name, when, app }], newest first.
    function parse(raw) {
        const out = [];
        // one bookmark at a time: dates are on the element, the app that
        // opened it (when the writer recorded one) is in its metadata child
        const tagRe = /<bookmark[\s][^>]*>/g;
        let m;
        while ((m = tagRe.exec(raw)) !== null) {
            const tag = m[0];
            const href = tag.match(/href="file:\/\/([^"]+)"/);
            if (!href) continue;
            const when = (tag.match(/\bmodified="([^"]+)"/) || tag.match(/\badded="([^"]+)"/)
                          || tag.match(/\bvisited="([^"]+)"/) || [])[1] || "";
            // the block between this tag and the next bookmark holds its metadata
            const next = /<bookmark[\s]/.exec(raw.slice(tagRe.lastIndex));
            const stop = next ? tagRe.lastIndex + next.index : raw.length;
            const app = (/<bookmark:application\b[^>]*\bname="([^"]+)"/.exec(raw.slice(tagRe.lastIndex, stop)) || [])[1] || "";
            const path = decodeURIComponent(href[1]);
            out.push({ path: path, name: path.split("/").pop(), when: when, app: app });
        }
        // ISO-8601 timestamps sort as strings
        return out.sort((a, b) => a.when < b.when ? 1 : (a.when > b.when ? -1 : 0)).slice(0, root.limit);
    }

    FileView {
        path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/recently-used.xbel"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.files = root.parse(text())
    }
}
