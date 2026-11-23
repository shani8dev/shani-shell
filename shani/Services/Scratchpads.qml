pragma Singleton
// Scratchpads (the drop-down terminal of Guake/Yakuake, Hyprland's special
// workspace): an app one key away, over whatever is open, and gone again on
// the same key. niri has no such thing, so it is the shell's minimise and
// restore: a pad's window floats near the top (niri's rule for app ids
// "shani-pad-*"); the key brings it to the workspace in front, or - when it is
// already there and focused - puts it away; not running, it is started.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    // [{ name, command, appId }] - appId is what the command's window gets (foot --app-id=…)
    readonly property var pads: Settings.data.scratchPads || []
    property string last: ""             // what the last toggle did (the tests)

    // the AI console (after Omarchy 4.5's): an AI agent's terminal dropped down over
    // the desktop on Mod+Shift+` - the first press starts it, later ones bring the
    // same session back. The agent: Settings' choice, else the first installed
    property string agentFound: ""
    readonly property string agent: Settings.data.aiConsoleAgent || agentFound
    readonly property var aiPad: ({ name: "ai", appId: "shani-pad-ai",
        command: "foot --app-id=shani-pad-ai " + (agent !== "" ? agent
            : "sh -c 'echo \"No AI agent is installed (claude, codex, opencode, gemini, aichat, ollama).\"; echo; exec $SHELL'") })
    Process {
        running: true
        command: ["sh", "-c", "for a in claude codex opencode gemini crush aichat; do command -v $a >/dev/null && { echo $a; exit; }; done; command -v ollama >/dev/null && echo 'ollama run llama3.2'"]
        stdout: StdioCollector { onStreamFinished: root.agentFound = text.trim() }
    }
    function find(name) { return pads.find(p => p.name === name) || (name === "ai" ? aiPad : null); }
    // the pad's window, if it is running (appId is what its command sets)
    function windowFor(name) {
        const pad = find(name);
        return pad && pad.appId ? Object.values(Niri.windows || {}).find(x => x.app_id === pad.appId) : null;
    }
    // a minimised pad lives on niri's hidden workspace, so its workspace_id
    // differs from the one in front - that is the visible state callers want
    function isVisible(name) {
        const w = windowFor(name);
        const here = (Niri.workspaces || []).find(x => x.is_focused);
        return !!w && !!here && w.workspace_id === here.id;
    }
    function show(name) {
        const w = windowFor(name);
        if (!w) return false;
        Niri.restore(w.id);
        last = "shown";
        return true;
    }
    function hide(name) {
        const w = windowFor(name);
        if (!w) return false;
        Niri.minimise(w.id);
        last = "hidden";
        return true;
    }
    function toggle(name) {
        const key = name || "terminal";
        const pad = find(key);
        if (!pad)
            return;
        const w = windowFor(key);
        if (!w) {
            last = "started";
            Quickshell.execDetached(["sh", "-c", pad.command]);
        } else if (isVisible(key) && w.id === Niri.focusedWindowId)
            hide(key);
        else
            show(key);
    }
}
