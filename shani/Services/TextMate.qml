pragma Singleton
// TextMate: discover .tmLanguage grammars and .tmTheme themes from bundle
// folders (~/.local/share/shani-textmate/, /usr/share/shani-shell/textmate/),
// load them through bridge/textmate.py (plist -> JSON), and highlight text.
// The Text Editor uses this when a grammar matches the file type, falling
// back to the built-in regex highlighter (Common/Highlight.js) otherwise.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../../Common/TextMate.js" as TM

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_TEXTMATE_TOOL") || "/usr/lib/shani-shell/textmate.py"
    readonly property var bundleDirs: [
        (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/shani-textmate",
        "/usr/share/shani-shell/textmate"
    ]

    property var grammars: []            // [{ name, scopeName, fileTypes, path }]
    property var themes: []              // [{ name, path }]
    property var loadedGrammars: ({})    // path -> normalized grammar object
    property var loadedThemes: ({})      // path -> theme array
    property string themePath: ""        // the active theme (from Settings)
    property bool enabled: Settings.data.textmateEnabled !== false

    function refresh() {
        dirIndex = 0;
        scanNext();
    }
    property int dirIndex: 0

    function scanNext() {
        if (dirIndex >= bundleDirs.length) return;
        scanProc.command = ["python3", root.tool, "list", bundleDirs[dirIndex]];
        scanProc.running = true;
    }

    function loadGrammar(g) {
        if (loadedGrammars[g.path]) return;
        const p = loadProc.createObject(root, { "command": ["python3", root.tool, "grammar", g.path] });
        p.onStreamFinished = txt => {
            try { const obj = JSON.parse(txt); const m = Object.assign({}, loadedGrammars); m[g.path] = obj; loadedGrammars = m; } catch (e) {}
            p.destroy();
        };
        p.running = true;
    }
    function loadTheme(t) {
        if (loadedThemes[t.path]) return;
        const p = loadProc.createObject(root, { "command": ["python3", root.tool, "theme", t.path] });
        p.onStreamFinished = txt => {
            try { const arr = JSON.parse(txt); const m = Object.assign({}, loadedThemes); m[t.path] = arr; loadedThemes = m; } catch (e) {}
            p.destroy();
        };
        p.running = true;
    }

    // choose a grammar for an extension, loading it first if needed
    function grammarFor(ext) {
        const g = TM.grammarFor(ext, grammars);
        if (g) loadGrammar(g);
        return g || null;
    }

    // highlight text with the given grammar (or one chosen by extension)
    function highlight(text, ext) {
        if (!enabled) return "";
        const g = ext ? TM.grammarFor(ext, grammars) : null;
        if (!g) return "";
        loadGrammar(g);
        const grammar = loadedGrammars[g.path];
        if (!grammar) return "";
        const theme = themePath && loadedThemes[themePath] ? loadedThemes[themePath] : [];
        return TM.highlight(text, grammar, theme);
    }

    property Component procComponent: Component { Process { } }
    property var loadProc: procComponent

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const gs = root.grammars.slice(), ts = root.themes.slice();
                    for (const g of (d.grammars || [])) if (!gs.some(x => x.path === g.path)) gs.push(g);
                    for (const t of (d.themes || [])) if (!ts.some(x => x.path === t.path)) ts.push(t);
                    root.grammars = gs; root.themes = ts;
                    // load all themes so highlights work
                    for (const t of root.themes) root.loadTheme(t);
                    if (!root.themePath && root.themes.length > 0) root.themePath = root.themes[0].path;
                } catch (e) {}
                root.dirIndex++;
                root.scanNext();
            }
        }
        onExited: code => { if (code !== 0) { root.dirIndex++; root.scanNext(); } }
    }

    Component.onCompleted: refresh()
}