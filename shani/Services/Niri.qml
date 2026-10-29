pragma Singleton
// niri's own event stream ($NIRI_SOCKET, "EventStream"): workspaces, windows,
// focus, keyboard layouts and overview, pushed as they change — no polling.
// Actions go through `niri msg action`, the same path a keybind uses.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Quickshell.env("NIRI_SOCKET") !== ""
    property var workspaces: []          // sorted by output, then idx
    property var windows: ({})           // id -> window
    property var focusedWindowId: null
    readonly property var focusedWindow: focusedWindowId === null ? null : (windows[focusedWindowId] || null)
    readonly property string focusedOutput: {
        const ws = workspaces.find(w => w.is_focused);
        return ws ? ws.output : "";
    }
    property var layouts: []
    property int layoutIndex: 0
    readonly property string layout: layouts[layoutIndex] || ""
    property bool overviewOpen: false
    signal screenshotSaved(string path)
    property var focusOrder: []          // window ids, most recently focused first

    function mru() {
        const seen = new Set(focusOrder.filter(id => windows[id]));
        const rest = Object.keys(windows).map(Number).filter(id => !seen.has(id));
        return [...seen, ...rest].map(id => windows[id]);
    }
    function workspaceLabel(id) {
        const w = workspaces.find(x => x.id === id);
        return w ? (w.name || "Workspace " + w.idx) : "";
    }
    onFocusedWindowIdChanged: {
        if (focusedWindowId !== null)
            focusOrder = [focusedWindowId].concat(focusOrder.filter(id => id !== focusedWindowId)).slice(0, 64);
    }

    function workspacesOn(output) {
        return workspaces.filter(w => w.output === output && w.name !== hiddenName);
    }

    // ---- minimise and show desktop (niri has neither) ------------------------
    // A minimised window lives on a workspace named "minimised": the empty one
    // niri always keeps at the end, named the first time (set-workspace-name),
    // so the workspaces before it keep their numbers. The bar, the dock and
    // Alt+Tab treat it as hidden; activating a window there brings it back to
    // the workspace in front of you.
    readonly property string hiddenName: "minimised"
    readonly property var hiddenWorkspace: workspaces.find(w => w.name === hiddenName) || null
    function isMinimised(w) { return !!w && hiddenWorkspace !== null && w.workspace_id === hiddenWorkspace.id; }
    readonly property var minimised: Object.values(windows).filter(w => isMinimised(w))
    function minimise(id) {
        if (hiddenWorkspace) {
            action("move-window-to-workspace", "--window-id", id, "--focus", "false", hiddenName);
            return;
        }
        // naming is not instant: windows put away in the same moment (show
        // desktop) all go to the workspace chosen for the first
        if (pendingIdx < 0) {
            const ws = workspaces.filter(w => w.output === focusedOutput).sort((a, b) => a.idx - b.idx);
            const last = ws[ws.length - 1];
            if (!last) return;
            pendingIdx = last.idx;
            pendingReset.restart();
            Quickshell.execDetached(["sh", "-c", 'niri msg action move-window-to-workspace --window-id "$1" --focus false "$2" && niri msg action set-workspace-name --workspace "$2" "$3"',
                                     "sh", String(id), String(pendingIdx), hiddenName]);
            return;
        }
        action("move-window-to-workspace", "--window-id", id, "--focus", "false", pendingIdx);
    }
    property int pendingIdx: -1
    Timer { id: pendingReset; interval: 1500; onTriggered: root.pendingIdx = -1 }
    function restore(id) {
        const here = workspaces.find(w => w.is_focused);
        if (here)
            action("move-window-to-workspace", "--window-id", id, "--focus", "true", here.idx);
        action("focus-window", "--id", id);
    }
    // every activation of a window goes through here: a minimised one comes back
    function focusWin(w) {
        if (isMinimised(w)) restore(w.id);
        else action("focus-window", "--id", w.id);
    }
    // show the desktop: this workspace's windows away; again, the same ones back
    property var desktopShown: []        // window ids put away by show desktop
    function showDesktop() {
        const back = desktopShown.filter(id => windows[id] && isMinimised(windows[id]));
        if (back.length) {
            back.forEach(id => restore(id));
            desktopShown = [];
            return;
        }
        const here = workspaces.find(w => w.is_focused);
        const ids = Object.values(windows).filter(w => here && w.workspace_id === here.id).map(w => w.id);
        ids.forEach(id => minimise(id));
        desktopShown = ids;
    }

    // ---- on every workspace (a Picture-in-Picture video, a call): niri keeps a
    // window on one workspace, so a pinned one floats and is carried to each
    // workspace as it is shown. Videos' own PiP windows are pinned as they open.
    property var pinned: []              // window ids
    readonly property var pipTitle: /^picture.in.picture$/i
    function isPinned(id) { return pinned.indexOf(id) >= 0; }
    function togglePinned(id) {
        if (isPinned(id)) {
            pinned = pinned.filter(x => x !== id);
            return;
        }
        pinned = pinned.concat([id]);
        const w = windows[id];
        if (w && !w.is_floating)
            action("move-window-to-floating", "--id", id);
    }
    // whichever event says so (a workspace focused, one moved, a monitor focused)
    readonly property var focusedWorkspaceId: { const w = workspaces.find(x => x.is_focused); return w ? w.id : null; }
    onFocusedWorkspaceIdChanged: if (pinned.length) carryPinned()
    function carryPinned() {
        const here = workspaces.find(w => w.is_focused);
        if (!here || here.name === hiddenName)
            return;
        for (const id of pinned) {
            const w = windows[id];
            if (w && w.workspace_id !== here.id && !isMinimised(w))
                action("move-window-to-workspace", "--window-id", id, "--focus", "false", here.idx);
        }
    }

    // ---- windows by name (for scripts, automations, Chronoa, and a phone over
    // SSH - after niri-remote and the niri-ipc agent skill): a loose match on
    // the title or app id, the one in front of you first, then the most recent
    function findWindows(q) {
        const t = (q || "").toLowerCase().trim();
        if (!t) return [];
        const here = workspaces.find(w => w.is_focused);
        const hit = mru().filter(w => (w.title || "").toLowerCase().includes(t) || (w.app_id || "").toLowerCase().includes(t));
        return hit.filter(w => here && w.workspace_id === here.id).concat(hit.filter(w => !here || w.workspace_id !== here.id));
    }
    // to: a workspace number (on the window's monitor), a monitor's name, or a workspace's name
    function moveWindowTo(w, to) {
        const outs = [...new Set(workspaces.map(x => x.output))];
        if (/^\d+$/.test(to))
            action("move-window-to-workspace", "--window-id", w.id, "--focus", "false", to);
        else if (outs.indexOf(to) >= 0)
            action("move-window-to-monitor", "--id", w.id, to);
        else
            action("move-window-to-workspace", "--window-id", w.id, "--focus", "false", to);
    }

    // ---- swap what two monitors show (niri-remote's): the workspace in front on
    // each changes places, and each column is snapped to the nearest of the usual
    // widths of its new screen, so a half stays a half from an ultrawide to a 16:9
    function snapWidth(px, screenPx) {
        const r = px / Math.max(1, screenPx) * 100;
        return r > 85 ? 100 : r > 60 ? 66.667 : r > 40 ? 50 : r > 28 ? 33.333 : 25;
    }
    function swapMonitors(outputWidths) {
        const outs = [...new Set(workspaces.map(x => x.output))];
        if (outs.length < 2)
            return false;
        const a = focusedOutput || outs[0], b = outs.find(o => o !== a);
        const wa = workspaces.find(w => w.output === a && w.is_active), wb = workspaces.find(w => w.output === b && w.is_active);
        if (!wa || !wb)
            return false;
        const widths = [];
        for (const w of Object.values(windows)) {
            const from = w.workspace_id === wa.id ? a : w.workspace_id === wb.id ? b : "";
            if (from && !w.is_floating && w.layout && w.layout.tile_size)
                widths.push(w.id, snapWidth(w.layout.tile_size[0], outputWidths[from] || 1920).toFixed(3) + "%");
        }
        // b's workspace is named for a moment: unnamed ones are known by number, which the move shifts
        Quickshell.execDetached(["sh", "-c", 'a=$1 b=$2 old=$3 keep=$4; shift 4
            niri msg action focus-monitor "$b" && niri msg action set-workspace-name shani-swap
            niri msg action focus-monitor "$a" && niri msg action move-workspace-to-monitor "$b"
            niri msg action move-workspace-to-monitor --reference shani-swap "$a"
            if [ -n "$old" ]; then niri msg action set-workspace-name --workspace shani-swap "$old"; else niri msg action unset-workspace-name shani-swap; fi
            while [ $# -ge 2 ]; do niri msg action focus-window --id "$1" && niri msg action set-column-width "$2"; shift 2; done
            [ -n "$keep" ] && niri msg action focus-window --id "$keep"; true',
            "sh", a, b, wb.name || "", focusedWindowId === null ? "" : String(focusedWindowId)].concat(widths.map(String)));
        return true;
    }

    function action(...args) {
        Quickshell.execDetached(["niri", "msg", "action", ...args.map(String)]);
    }

    function findWindow(q) {
        const low = String(q || "").toLowerCase();
        if (!low)
            return null;
        const wins = Object.values(windows);
        let w = wins.find(x => (x.title || "").toLowerCase() === low || (x.app_id || "").toLowerCase() === low);
        if (!w)
            w = wins.find(x => (x.title || "").toLowerCase().indexOf(low) >= 0 || (x.app_id || "").toLowerCase().indexOf(low) >= 0);
        return w || null;
    }

    function focusWorkspace(ws) {
        if (ws.output !== focusedOutput)
            action("focus-monitor", ws.output);
        action("focus-workspace", ws.idx);
    }

    // ---- smart window actions by title (niri-remote style) ----------------
    function closeWindow(q) {
        const w = findWindow(q);
        if (w) action("close-window", "--id", w.id);
        return !!w;
    }
    function fullscreenWindow(q) {
        const w = findWindow(q);
        if (w) action("fullscreen-window", "--id", w.id);
        return !!w;
    }
    function minimiseWindowByTitle(q) {
        const w = findWindow(q);
        if (w) minimise(w.id);
        return !!w;
    }
    function focusWindowByTitle(q) {
        const w = findWindow(q);
        if (w) focusWin(w);
        return !!w;
    }

    function handle(ev) {
        if (ev.WorkspacesChanged) {
            workspaces = ev.WorkspacesChanged.workspaces.slice().sort((a, b) => a.output === b.output ? a.idx - b.idx : (a.output < b.output ? -1 : 1));
        } else if (ev.WorkspaceActivated) {
            const id = ev.WorkspaceActivated.id;
            const target = workspaces.find(w => w.id === id);
            if (!target)
                return;
            workspaces = workspaces.map(w => {
                const c = Object.assign({}, w);
                if (w.output === target.output)
                    c.is_active = w.id === id;
                if (ev.WorkspaceActivated.focused)
                    c.is_focused = w.id === id;
                return c;
            });
        } else if (ev.WorkspaceActiveWindowChanged) {
            const e = ev.WorkspaceActiveWindowChanged;
            workspaces = workspaces.map(w => w.id === e.workspace_id ? Object.assign({}, w, { active_window_id: e.active_window_id }) : w);
        } else if (ev.WorkspaceUrgencyChanged) {
            const e = ev.WorkspaceUrgencyChanged;
            workspaces = workspaces.map(w => w.id === e.id ? Object.assign({}, w, { is_urgent: e.urgent }) : w);
        } else if (ev.WindowsChanged) {
            const m = {};
            let focused = null;
            for (const w of ev.WindowsChanged.windows) {
                m[w.id] = w;
                if (w.is_focused)
                    focused = w.id;
            }
            windows = m;
            focusedWindowId = focused;
        } else if (ev.WindowOpenedOrChanged) {
            const w = ev.WindowOpenedOrChanged.window;
            if (!windows[w.id] && pipTitle.test(w.title || "") && !isPinned(w.id))
                togglePinned(w.id);
            const m = Object.assign({}, windows);
            m[w.id] = w;
            windows = m;
            if (w.is_focused)
                focusedWindowId = w.id;
        } else if (ev.WindowClosed) {
            const m = Object.assign({}, windows);
            delete m[ev.WindowClosed.id];
            windows = m;
            if (isPinned(ev.WindowClosed.id))
                pinned = pinned.filter(x => x !== ev.WindowClosed.id);
            if (focusedWindowId === ev.WindowClosed.id)
                focusedWindowId = null;
        } else if (ev.WindowFocusChanged) {
            focusedWindowId = ev.WindowFocusChanged.id;
        } else if (ev.KeyboardLayoutsChanged) {
            layouts = ev.KeyboardLayoutsChanged.keyboard_layouts.names;
            layoutIndex = ev.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
        } else if (ev.KeyboardLayoutSwitched) {
            layoutIndex = ev.KeyboardLayoutSwitched.idx;
        } else if (ev.ScreenshotCaptured) {
            if (ev.ScreenshotCaptured.path)
                screenshotSaved(ev.ScreenshotCaptured.path);
        } else if (ev.OverviewOpenedOrClosed) {
            overviewOpen = ev.OverviewOpenedOrClosed.is_open;
        }
    }

    Socket {
        id: stream
        path: Quickshell.env("NIRI_SOCKET")
        connected: root.available
        onConnectedChanged: {
            if (connected) {
                write('"EventStream"\n');
                flush();
            }
        }
        parser: SplitParser {
            onRead: line => {
                let ev;
                try {
                    ev = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (!ev.Ok && !ev.Err)
                    root.handle(ev);
            }
        }
    }

    // niri restarts (config error, crash) close the stream; reconnect.
    Timer {
        interval: 1500
        running: root.available && !stream.connected
        repeat: true
        onTriggered: stream.connected = true
    }
}
