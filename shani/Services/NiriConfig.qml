pragma Singleton
// The shell's niri includes (InputConfig: keyboard, pointer, screens;
// WindowRules: per-app rules) are written through here, so a change niri
// cannot read is undone instead of leaving the desktop on its old settings
// with the file broken underneath:
//   - before a write, the file as it was is kept beside it as <file>.prev
//     (only when there is none yet: an unconfirmed write is never kept)
//   - niri reloads and says so on its event stream (Niri: ConfigLoaded)
//   - loaded fine: the .prev copies are deleted
//   - failed: each file written since is put back from its .prev, and the
//     person is told plainly which settings were not applied
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property var pending: ({})            // path -> what it holds, in words, written and not yet loaded
    property int undone: 0                // how many times a change was put back (for tests)
    property int rejected: 0              // how many changes niri validate refused before writing
    property string lastUndone: ""
    property string lastRejected: ""

    function write(path, text, label) {
        const p = proc.createObject(root, { path: path, label: label });
        // pre-flight: validate a candidate config beside the real one so its
        // relative includes resolve, and never touch the live file if niri
        // would reject it (niri-rules-studio / ArchWiki `niri validate`)
        p.command = ["sh", "-c", 'f=$1; t=$2; label=$3
            mkdir -p "${f%/*}" || exit 1
            [ -f "$f" ] && [ "$(cat "$f")" = "$(printf "%s" "$t")" ] && exit 3
            cand="$f.candidate"
            printf "%s" "$t" > "$cand"
            if command -v niri >/dev/null 2>&1 && ! niri validate -c "$cand" >/dev/null 2>&1; then
                printf "%s\\n" "niri rejected $label" > "$f.invalid"
                rm -f "$cand"; exit 4
            fi
            rm -f "$cand" "$f.invalid"
            if [ ! -f "$f.prev" ]; then
                if [ -f "$f" ]; then cp "$f" "$f.prev"; else printf "// written by shani-shell\\n" > "$f.prev"; fi
            fi
            printf "%s" "$t" > "$f.tmp" && mv "$f.tmp" "$f"', "sh", path, text, label];
        p.running = true;
    }
    Component {
        id: proc
        Process {
            property string path
            property string label
            onExited: code => {
                if (code === 0) {
                    const m = Object.assign({}, root.pending);
                    m[path] = label;
                    root.pending = m;
                } else if (code === 4) {
                    root.rejected++;
                    root.lastRejected = label;
                    Quickshell.execDetached(["notify-send", "-a", Tr.t("Settings"), "-i", "dialog-warning",
                        Tr.t("The change was not applied"),
                        Tr.t("Niri would reject the new %1, so nothing was changed.").replace("%1", label)]);
                }
                destroy();
            }
        }
    }

    Connections {
        target: Niri
        function onConfigLoaded(failed) {
            const paths = Object.keys(root.pending);
            if (!paths.length)
                return;
            const labels = [...new Set(paths.map(p => root.pending[p]))];
            root.pending = {};
            if (!failed) {
                Quickshell.execDetached(["sh", "-c", 'for f; do rm -f "$f.prev"; done', "sh"].concat(paths));
                return;
            }
            Quickshell.execDetached(["sh", "-c", 'for f; do [ -f "$f.prev" ] && mv -f "$f.prev" "$f"; done', "sh"].concat(paths));
            root.undone++;
            root.lastUndone = labels.join(", ");
            Quickshell.execDetached(["notify-send", "-a", Tr.t("Settings"), "-i", "dialog-warning",
                Tr.t("A change could not be applied"),
                Tr.t("The desktop could not use the new settings for %1, so the previous ones were put back.").replace("%1", root.lastUndone)]);
        }
    }
}
