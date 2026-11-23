pragma Singleton
// Window preview on hover: a cropped capture of the window's on-screen area,
// via grim over wlr-screencopy (niri offers it). Niri has no per-window capture
// protocol, so we use the window's workspace-view geometry from its event
// stream, clipped to the output's logical rect. Only the currently visible
// region can be captured — a hidden/overlapped window shows what is on top.
// Cached by window id for a short TTL; one capture per hover settle.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string path: ""           // the captured PNG
    property string title: ""
    property string windowId: ""
    readonly property bool shown: path !== ""
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-shell-preview"

    function capture(win, outName) {
        if (!win || !win.layout) { clear(); return; }
        const L = win.layout;
        const pos = L.tile_pos_in_workspace_view;
        const size = L.tile_size;
        if (!pos || !size || pos.length < 2 || size.length < 2) { clear(); return; }
        const o = (typeof outName === "string" ? Displays.outputs.find(d => d.name === outName) : outName) || {};
        const ox = o.x || 0, oy = o.y || 0, ow = o.width || 0, oh = o.height || 0;
        let x = ox + pos[0], y = oy + pos[1], w = size[0], h = size[1];
        if (w <= 0 || h <= 0 || ow <= 0 || oh <= 0) { clear(); return; }
        // clip to the output so grim never grabs outside the screen
        const x1 = Math.max(x, ox), y1 = Math.max(y, oy);
        const x2 = Math.min(x + w, ox + ow), y2 = Math.min(y + h, oy + oh);
        x = x1; y = y1; w = x2 - x1; h = y2 - y1;
        if (w <= 4 || h <= 4) { clear(); return; }
        const file = dir + "/win-" + String(win.id) + ".png";
        if (path === file && clearTimer.running) { clearTimer.restart(); return; }
        Quickshell.execDetached(["mkdir", "-p", dir]);
        cap.pendingFile = file;
        cap.pendingTitle = win.title || win.app_id || "";
        cap.pendingId = String(win.id);
        cap.command = ["sh", "-c",
            'g="$1"; out="$2"; grim -g "$g" "$out" 2>/dev/null && printf %s "$out"',
            "sh", x + "," + y + " " + w + "x" + h, file];
        cap.running = true;
        clearTimer.restart();
    }
    Process {
        id: cap
        property string pendingFile: ""
        property string pendingTitle: ""
        property string pendingId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                // a capture from an earlier hover can finish after the pending
                // fields moved to another window: never show its image with the
                // new window's title/id (or resurrect it after clear())
                if (out !== "" && out === cap.pendingFile) {
                    root.path = out;
                    root.title = cap.pendingTitle;
                    root.windowId = cap.pendingId;
                }
            }
        }
        stderr: StdioCollector {}
    }
    Timer {
        id: clearTimer
        interval: 3000
        onTriggered: clear()
    }
    function clear() {
        cap.pendingFile = "";          // invalidate any capture still in flight
        path = ""; title = ""; windowId = "";
        clearTimer.stop();
    }
}
