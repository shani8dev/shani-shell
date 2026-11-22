pragma Singleton
// Keyring: generic secrets in the desktop keyring (Secret Service) through
// bridge/passwords.py. Used by AI providers and encrypted screenshot history.
// Secrets are read from/written to stdin, never on a command line.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_PASSWORDS_TOOL") || "/usr/lib/shani-shell/passwords.py"

    function get(id, cb) {
        const p = getProc.createObject(root, {});
        p._cb = cb;
        // look up by attribute: `set` stores a new item with shani-id, because
        // passwords.py `set` expects a D-Bus object path, not an arbitrary name.
        p.command = ["python3", root.tool, "lookup", id];
        p.running = true;
        return p;
    }
    function set(id, value) {
        // Secret Service `add` takes a collection path, a label and attributes.
        // The `default` alias is resolved inside passwords.py's add() caller.
        const payload = JSON.stringify({ secret: value });
        Quickshell.execDetached(["sh", "-c",
            'printf %s "$2" | python3 "$1" put "$3" >/dev/null 2>&1 || true',
            "sh", root.tool, payload, id]);
    }
    function remove(id) {
        Quickshell.execDetached(["sh", "-c",
            'python3 "$1" drop "$2" >/dev/null 2>&1 || true',
            "sh", root.tool, id]);
    }

    property Component getProc: Component {
        Process {
            property var _cb: null
            stdout: StdioCollector {
                onStreamFinished: {
                    let v = "";
                    try { v = (JSON.parse(text) || {}).secret || ""; } catch (e) {}
                    if (_cb) _cb(v);
                    destroy();
                }
            }
            onExited: code => { if (code !== 0 && _cb) { _cb(""); destroy(); } }
        }
    }
}