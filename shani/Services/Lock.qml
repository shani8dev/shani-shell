pragma Singleton
// Lock state, the one thing every lock path converges on: the keybind / IPC,
// the idle timer, `loginctl lock-session` and "about to suspend" (both from
// logind, relayed by the bridge). The surface itself is Modules/Lock.
// logind is told back (LockedHint) so `loginctl` and other tools see it, and
// the bridge releases its sleep delay only once the lock is really up.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    property bool locked: false
    property bool secure: false     // set by the WlSessionLock once every output is covered

    // A locked shell must not leave vault plaintext readable: drop every gocryptfs mount
    // on lock/suspend via the same bridge tool Files uses. Unlocking only clears the UI —
    // remounting is out of scope (each vault is reopened with its password in Files).
    readonly property string lockTool: Quickshell.env("SHANI_LOCK_TOOL") || "/usr/lib/shani-shell/lock.py"

    function closeVaults() {
        if (!vaultCloser.running)
            vaultCloser.running = true;
    }
    Process {
        id: vaultCloser
        command: ["python3", root.lockTool, "vault-close-all"]
    }

    function lock() {
        locked = true;
        closeVaults();
    }
    function unlocked() {
        locked = false;
        secure = false;
        Bridge.send({ op: "locked", locked: false });
    }

    onSecureChanged: if (secure) Bridge.send({ op: "locked", locked: true })

    Connections {
        target: Bridge
        function onMessage(m) {
            if (m.type === "logind" && m.op === "lock")
                root.lock();
            else if (m.type === "logind" && m.op === "sleep") {
                if (Settings.data.lockBeforeSuspend)
                    root.lock();
                else {
                    root.closeVaults();   // suspend must close vaults even without a lock
                    Bridge.send({ op: "release-sleep" });
                }
            }
            else if (m.type === "logind" && m.op === "unlock")
                root.unlocked();
        }
    }
}
