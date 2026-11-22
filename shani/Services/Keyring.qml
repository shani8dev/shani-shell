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
        p.command = ["python3", root.tool, "reveal", id];
        p.running = true;
        return p;
    }
    function set(id, value) {
        Quickshell.execDetached(["sh", "-c",
            'printf %s "$2" | python3 "$1" set "$3" >/dev/null 2>&1 || true',
            "sh", root.tool, value, id]);
    }
    function remove(id) {
        Quickshell.execDetached(["sh", "-c",
            'python3 "$1" delete "$2" >/dev/null 2>&1 || true',
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