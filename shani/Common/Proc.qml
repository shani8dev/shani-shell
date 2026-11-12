pragma Singleton
// Proc: run a command and answer when it ends - with a debounce and a
// timeout, so neither a burst of calls nor a command that hangs can wedge
// the shell.
//
//   Proc.run("files-list", ["ls", path], (out, code) => { ... });
//   Proc.run("files-list", cmd, cb, 0, 5000);   // no debounce, 5 s timeout
//
// The same id is one slot: calling it again with the same id replaces the
// command and restarts the debounce, so a watcher that fires every second
// runs the command once, when it settles. `release(id)` gives the slot back.
//
// The callback is not called if the caller is gone (a panel that closed
// while its command was running): a destroyed QObject still reads as truthy,
// so `Qt.isQtObject` is the only reliable liveness probe.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property var log: Log.scoped("Proc")
    readonly property int defaultDebounceMs: 50
    readonly property int defaultTimeoutMs: 15000
    readonly property int noTimeout: -1

    property var _slots: ({})     // id -> { timer, command, callback, timeoutMs, owner }

    // id: the slot (the same id is one command); command: the argv; cb: (out, code)
    // debounceMs: how long to wait for the calls to settle; timeoutMs: when to give up
    function run(id, command, cb, debounceMs, timeoutMs, owner) {
        if (!id || !command)
            return;
        const wait = (typeof debounceMs === "number" && debounceMs >= 0) ? debounceMs : root.defaultDebounceMs;
        const limit = (typeof timeoutMs === "number") ? timeoutMs : root.defaultTimeoutMs;
        let slot = root._slots[id];
        if (!slot) {
            slot = {
                "timer": timerComponent.createObject(root),
                "command": command,
                "callback": cb || null,
                "timeoutMs": limit,
                "owner": owner || null
            };
            slot.timer.triggered.connect(function () { root._launch(id); });
            root._slots[id] = slot;
        } else {
            slot.command = command;
            slot.callback = cb || null;
            slot.timeoutMs = limit;
            slot.owner = owner || null;
        }
        slot.timer.interval = wait;
        slot.timer.restart();
    }

    function release(id) {
        const slot = root._slots[id];
        if (!slot)
            return;
        slot.callback = null;
        try {
            slot.timer.stop();
            slot.timer.destroy();
        } catch (e) { }
        delete root._slots[id];
    }

    function _launch(id) {
        const slot = root._slots[id];
        if (!slot || !slot.command)
            return;
        if (slot.owner && !Qt.isQtObject(slot.owner)) {
            root.release(id);
            return;
        }
        const proc = processComponent.createObject(root, { "command": slot.command });
        const timer = timerComponent.createObject(root);
        let out = "";
        let err = "";
        let outSeen = false;
        let errSeen = false;
        let exited = false;
        let code = -1;

        function done() {
            if (!exited || !outSeen || !errSeen)
                return;
            timer.stop();
            const cb = slot.callback;
            if (cb && !(slot.owner && !Qt.isQtObject(slot.owner))) {
                try {
                    cb(out, code);
                } catch (e) {
                    root.log.warn("callback failed:", slot.command, e);
                }
            }
            try {
                proc.destroy();
            } catch (e) { }
            try {
                timer.destroy();
            } catch (e) { }
            slot.command = null;
            slot.callback = null;
            slot.owner = null;
        }

        timer.interval = slot.timeoutMs;
        timer.triggered.connect(function () {
            if (exited)
                return;
            // it hung: stop it and answer, so the caller is not left waiting
            exited = true;
            code = 124;
            proc.running = false;
            done();
        });

        proc.stdout.streamFinished.connect(function () {
            out = proc.stdout.text || "";
            outSeen = true;
            done();
        });
        proc.stderr.streamFinished.connect(function () {
            err = proc.stderr.text || "";
            errSeen = true;
            done();
        });
        proc.exited.connect(function (c) {
            exited = true;
            code = c;
            done();
        });

        proc.running = true;
        if (slot.timeoutMs !== root.noTimeout)
            timer.start();
    }

    Component {
        id: timerComponent
        Timer { repeat: false }
    }

    Component {
        id: processComponent
        Process {
            running: false
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
}
