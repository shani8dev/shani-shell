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
        return workspaces.filter(w => w.output === output);
    }

    function action(...args) {
        Quickshell.execDetached(["niri", "msg", "action", ...args.map(String)]);
    }

    function focusWorkspace(ws) {
        if (ws.output !== focusedOutput)
            action("focus-monitor", ws.output);
        action("focus-workspace", ws.idx);
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
            const m = Object.assign({}, windows);
            m[w.id] = w;
            windows = m;
            if (w.is_focused)
                focusedWindowId = w.id;
        } else if (ev.WindowClosed) {
            const m = Object.assign({}, windows);
            delete m[ev.WindowClosed.id];
            windows = m;
            if (focusedWindowId === ev.WindowClosed.id)
                focusedWindowId = null;
        } else if (ev.WindowFocusChanged) {
            focusedWindowId = ev.WindowFocusChanged.id;
        } else if (ev.KeyboardLayoutsChanged) {
            layouts = ev.KeyboardLayoutsChanged.keyboard_layouts.names;
            layoutIndex = ev.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
        } else if (ev.KeyboardLayoutSwitched) {
            layoutIndex = ev.KeyboardLayoutSwitched.idx;
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
