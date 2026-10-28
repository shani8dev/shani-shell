pragma Singleton
// The shell's one line to its Python bridge (bridge/chronoa-bridge.py): JSON
// lines over $XDG_RUNTIME_DIR/shani-chronoa.sock. Chronoa traffic and logind
// (lock / sleep) both ride it; consumers listen to `message`.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property bool connected: sock.connected
    signal message(var msg)

    function send(obj) {
        if (!sock.connected)
            return false;
        sock.write(JSON.stringify(obj) + "\n");
        sock.flush();
        return true;
    }

    Socket {
        id: sock
        // Agree on the runtime dir, not a literal /run/user/0: on a normal
        // account the socket lives under /run/user/1000.
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/0") + "/shani-chronoa.sock"
        connected: true
        parser: SplitParser {
            onRead: line => {
                try {
                    root.message(JSON.parse(line));
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 2000
        running: !sock.connected
        repeat: true
        onTriggered: sock.connected = true
    }
}
