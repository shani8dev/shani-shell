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
    function toggle(name) {
        const pad = find(name || "terminal");
        if (!pad)
            return;
        const w = Object.values(Niri.windows).find(x => x.app_id === pad.appId);
        const here = Niri.workspaces.find(x => x.is_focused);
        if (!w) {
            last = "started";
            Quickshell.execDetached(["sh", "-c", pad.command]);
        } else if (w.id === Niri.focusedWindowId && here && w.workspace_id === here.id) {
            last = "hidden";
            Niri.minimise(w.id);
        } else {
            last = "shown";
            Niri.restore(w.id);
        }
    }
}
