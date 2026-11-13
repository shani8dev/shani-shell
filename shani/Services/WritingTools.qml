pragma Singleton
// Writing tools: select text in any app, press Mod+Shift+W (or pick "Writing
// tools" in the launcher), choose what to do with it - proofread, rewrite,
// friendlier, shorter, a list, a translation - and Chronoa writes it
// (Agent.Write: the model alone, no tools, no conversation). Replace puts the
// result where the selection was: copied, then pasted into the window that
// was focused (Ctrl+Shift+V in a terminal); Copy only copies.
//
// The text is the primary selection (what is highlighted), else the clipboard.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool shown: false
    property string source: ""          // the text to work on
    property string from: ""            // "selection" | "clipboard"
    property string result: ""
    property string error: ""
    property bool busy: false
    property string doing: ""           // the label of what was asked
    property string lastInstruction: ""
    property int windowId: -1           // where Replace pastes
    property string windowApp: ""
    property int seq: 0

    readonly property var presets: [
        { label: Tr.t("Proofread"), icon: "tools-check-spelling", instruction: "Fix spelling, grammar and punctuation. Change nothing else." },
        { label: Tr.t("Rewrite"), icon: "edit-rename", instruction: "Rewrite this to read more clearly, keeping its meaning and about its length." },
        { label: Tr.t("Friendlier"), icon: "face-smile", instruction: "Rewrite this in a warmer, friendlier tone." },
        { label: Tr.t("Professional"), icon: "x-office-document", instruction: "Rewrite this in a clear, professional tone." },
        { label: Tr.t("Shorter"), icon: "zoom-out", instruction: "Make this shorter, keeping what matters." },
        { label: Tr.t("Longer"), icon: "zoom-in", instruction: "Expand this a little with helpful detail. Do not invent facts." },
        { label: Tr.t("Bullet points"), icon: "view-list", instruction: "Turn this into a short bulleted list." },
        { label: Tr.t("Summary"), icon: "view-paged", instruction: "Summarise this in two or three sentences." }
    ]
    readonly property var languages: ["English", "हिन्दी", "मराठी", "Español", "Français", "Deutsch", "Português", "日本語"]

    function open() {
        result = "";
        error = "";
        busy = false;
        source = "";
        // where the text came from, so Replace can go back there
        windowId = Niri.focusedWindowId !== undefined && Niri.focusedWindowId !== null ? Niri.focusedWindowId : -1;
        const w = Niri.windows[windowId];
        windowApp = w ? (w.app_id || "") : "";
        grab.running = false;
        grab.running = true;
        shown = true;
    }
    function close() { shown = false; }

    // the highlighted text, else what was copied
    Process {
        id: grab
        command: ["sh", "-c", 's=$(wl-paste --primary --no-newline 2>/dev/null); if [ -n "$s" ]; then printf "selection\\n%s" "$s"; else printf "clipboard\\n%s" "$(wl-paste --no-newline 2>/dev/null)"; fi']
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n");
                root.from = nl > 0 ? text.slice(0, nl) : "clipboard";
                root.source = nl > 0 ? text.slice(nl + 1) : "";
            }
        }
    }

    function run(instruction, label) {
        if (!source.trim() || !instruction.trim())
            return;
        seq++;
        busy = true;
        error = "";
        result = "";
        doing = label || instruction;
        lastInstruction = instruction;
        Bridge.send({ op: "write", id: "w" + seq, instruction: instruction, text: source });
    }
    function choose(i) { const p = presets[i]; if (p) run(p.instruction, p.label); }
    function translate(lang) { run("Translate this into " + lang + ".", Tr.t("Translate into %1", lang)); }
    function again() { if (lastInstruction) run(lastInstruction, doing); }

    Connections {
        target: Bridge
        function onMessage(msg) {
            if (msg.type !== "written" || msg.id !== "w" + root.seq)
                return;                     // an older request's answer: not what is asked now
            root.busy = false;
            if (msg.error) root.error = msg.error;
            else root.result = msg.text || "";
        }
    }

    readonly property bool terminal: /foot|kitty|alacritty|ghostty|wezterm|konsole|terminal|console|ptyxis|xterm/i.test(windowApp)
    // the result where the selection was: copied, the window refocused, pasted
    function replace() {
        if (!result)
            return;
        const text = result;
        close();
        Quickshell.execDetached(["sh", "-c",
            'printf "%s" "$1" | wl-copy; sleep 0.3; [ "$2" -ge 0 ] && niri msg action focus-window --id "$2"; sleep 0.2; if [ "$3" = 1 ]; then wtype -M ctrl -M shift v -m shift -m ctrl; else wtype -M ctrl v -m ctrl; fi',
            "sh", text, String(windowId), terminal ? "1" : "0"]);
    }
    function copy() {
        if (!result)
            return;
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", result]);
        close();
    }
}
