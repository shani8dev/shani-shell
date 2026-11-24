pragma Singleton
// The screen keyboard's brain. Keys are sent over niri's virtual-keyboard
// protocol (wtype builds a keymap for any Unicode it is given), so it types
// Devanagari as easily as Latin — and it does not take the input-method slot,
// so fcitx5 (Hindi phonetic on the hardware keyboard) keeps working beside it.
//
// Smart matras, as good Indic phone keyboards do: a vowel tapped right after a
// consonant becomes that vowel's sign (क + आ = का), so Marathi needs no
// separate matra page. Modules/Osk draws the keys.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "WriteLang.js" as WriteLang

Singleton {
    id: root

    property bool shown: false
    property int height: 0
    property string output: ""
    function heightOn(name) { return name === output ? height : 0; }
    property bool available: true          // wtype is a dependency of the shell
    readonly property var languages: Settings.data.oskLanguages
    property int langIndex: 0
    readonly property string lang: languages[langIndex % languages.length] || "en"
    property bool shift: false
    property string page: "letters"         // letters | symbols | write
    // Ctrl and Alt, sticky (a phone's way, for a keyboard without keys held down):
    // one tap - the next key only; a second tap - held until tapped again
    property int ctrl: 0                    // 0 off, 1 the next key, 2 held
    property int alt: 0
    function tapMod(name) { root[name] = (root[name] + 1) % 3; }
    function modArgs(down) {
        const m = (root.ctrl ? ["ctrl"] : []).concat(root.alt ? ["alt"] : []);
        return [].concat(...m.map(x => [down ? "-M" : "-m", x]));
    }
    function used() { if (ctrl === 1) ctrl = 0; if (alt === 1) alt = 0; }

    // ---- the keyboard's own controls ---------------------------------------
    // The ⚙ key on the keyboard is the only control (Settings has no OSK page).
    // Settings.data's JsonAdapter only accepts keys declared in Common/Settings.qml,
    // which the keyboard does not own, so these three live in a sibling file in
    // the same config dir. Defaults are declared on the adapter below.
    readonly property string prefsDir: {
        const p = Settings.path;
        return p.substring(0, p.lastIndexOf("/"));
    }
    readonly property string prefsPath: root.prefsDir + "/osk.json"
    FileView {
        id: prefsFile
        path: root.prefsPath
        atomicWrites: true
        printErrors: false
        JsonAdapter {
            id: prefs
            property string size: "fixed"
            property real panelOpacity: 1
            property bool suggestions: true
        }
    }
    property string size: prefs.size === "compact" ? "compact" : "fixed"
    property real panelOpacity: {
        const v = Number(prefs.panelOpacity);
        return v >= 0.55 && v <= 1 ? v : 1;
    }
    property bool suggestions: prefs.suggestions !== false
    readonly property bool compact: size === "compact"
    function savePrefs() {
        prefs.size = root.size;
        prefs.panelOpacity = root.panelOpacity;
        prefs.suggestions = root.suggestions;
        Quickshell.execDetached(["mkdir", "-p", root.prefsDir]);
        prefsFile.writeAdapter();
    }
    function toggleSize() { root.size = compact ? "fixed" : "compact"; savePrefs(); }
    function cycleOpacity() {
        const steps = [1, 0.85, 0.7];
        const at = steps.findIndex(v => Math.abs(v - root.panelOpacity) < 0.01);
        root.panelOpacity = steps[(at + 1) % steps.length];
        savePrefs();
    }
    function toggleSuggestions() { root.suggestions = !root.suggestions; savePrefs(); }

    // handwriting: rows of strokes read on this machine (Tesseract), typed in order
    readonly property string writeTool: Quickshell.env("SHANI_HANDWRITING_TOOL") || "/usr/lib/shani-shell/handwriting.py"
    // the Tesseract language handwriting is read in (WriteLang.js: the hand-made ones,
    // and the xkb layouts of the Indian languages the image ships data for)
    readonly property string writeLang: WriteLang.tesseractLang(lang)
    property bool reading: reader.running
    property string lastWritten: ""        // for the tests
    function recognize(rows) {
        reader.command = ["sh", "-c", 'printf "%s" "$1" | python3 "$2" "$3"', "sh", JSON.stringify(rows), writeTool, writeLang];
        reader.running = true;
    }
    // strokes already in a file (the IPC's way in: JSON cannot pass through its arguments)
    function recognizeFile(path) {
        reader.command = ["sh", "-c", 'python3 "$1" "$2" < "$3"', "sh", writeTool, writeLang, path];
        reader.running = true;
    }
    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                let rows = [];
                try { rows = JSON.parse(text).rows.filter(r => r !== ""); } catch (e) {}
                root.lastWritten = rows.join("\n");
                // one letter with Ctrl or Alt armed is a shortcut (Ctrl + a written c copies)
                if (rows.length === 1 && (root.ctrl || root.alt) && rows[0].length === 1) {
                    root.press(rows[0].toLowerCase());
                    return;
                }
                // the rows and the Returns between them one after another: a wtype per
                // row started side by side and interleaved them (HELL + TELL typed HTEELLLL)
                if (!rows.length)
                    return;
                Quickshell.execDetached(["sh", "-c", 'n=; for r; do [ -z "$n" ] || wtype -k Return; n=1; wtype -- "$r"; done', "sh"].concat(rows));
                root.typed = rows[rows.length - 1].slice(-16);
            }
        }
    }
    property string typed: ""               // the last few characters sent (for tests and smart matras)

    // ---- word suggestions --------------------------------------------------
    // A bounded, built-in list: no download, no dictionary service, no learning.
    // It only knows these common English words, and only the English layout.
    readonly property var suggestionWords: (
        "about above after again against all almost along already also always among another any are around "
        + "ask back be because been before being below best between both but by call can come could day "
        + "different do does done down during each early easy end enough even ever every few find first "
        + "five for from get give go good got great had has have he her here hello help him his how if in "
        + "into is it its just keep kind know last late learn left less let like little long look made make many may "
        + "me might more most much must my need never new next no not now of off often on once one only "
        + "or other our out over own people perhaps place put quite rather right said same say see seem "
        + "she should show since small so some someone something still such take than that the their them "
        + "then there these they thing think this those though through time to together too try two under "
        + "until up us use very want was way we well were what when where which while who why will with "
        + "without would write year yes yet you your"
    ).split(" ")
    readonly property int maxSuggestions: 5
    property string dismissedWord: ""       // the × hides this word, not every word

    function currentWord() {
        const m = String(typed).match(/[A-Za-z]+$/);
        return m ? m[0].toLowerCase() : "";
    }
    function suggestionsFor(word) {
        const w = String(word || "").toLowerCase();
        if (w.length < 2)
            return [];
        const out = root.suggestionWords.filter(x => x.length > w.length && x.startsWith(w));
        out.sort((a, b) => a.length - b.length || a.localeCompare(b));
        return out.slice(0, root.maxSuggestions);
    }
    function dismissSuggestions() { root.dismissedWord = root.currentWord(); }
    // Replace the word under the cursor. Remote mode edits its own draft;
    // otherwise wtype deletes the word and types the replacement in one go.
    function applySuggestion(word) {
        const w = root.currentWord();
        if (!w || !word)
            return;
        if (remote) {
            draft = draft.slice(0, draft.length - w.length) + word + " ";
            typed = draft.slice(-16);
        } else {
            const args = ["wtype"];
            for (let i = 0; i < w.length; i++)
                args.push("-k", "BackSpace");
            args.push("--", word + " ");
            Quickshell.execDetached(args);
            typed = (typed.slice(0, typed.length - w.length) + word + " ").slice(-16);
        }
        root.dismissedWord = "";
        shift = false;
    }

    // Layouts: "en" and "mr" are drawn by hand (mr with smart matras); any
    // other entry is an xkb layout id ("in+tam", "ru", "ara" …), generated
    // from the system's xkb data by osk-layout.py and cached here.
    property var xkb: ({})                  // id -> { name, rows: [[{n, s}]] }
    readonly property bool isXkb: lang !== "en" && lang !== "mr"
    readonly property var current: isXkb ? (xkb[lang] || null) : null
    readonly property string script: Quickshell.env("SHANI_OSK_LAYOUT_TOOL") || "/usr/lib/shani-shell/osk-layout.py"

    function load(id) {
        if (id === "en" || id === "mr" || xkb[id] !== undefined)
            return;
        const p = loader.createObject(root, { layoutId: id });
        p.running = true;
    }
    // a changed list keeps the language in use if it is still there, else the
    // first — never whatever now happens to sit at the old index
    property string was: "en"
    onLangChanged: was = lang
    onLanguagesChanged: {
        languages.forEach(load);
        const i = languages.indexOf(was);
        langIndex = i >= 0 ? i : 0;
    }
    Component.onCompleted: languages.forEach(load)
    Component {
        id: loader
        Process {
            id: proc
            property string layoutId
            command: ["python3", root.script, layoutId]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const m = Object.assign({}, root.xkb);
                        m[proc.layoutId] = JSON.parse(text);
                        root.xkb = m;
                    } catch (e) {}
                    proc.destroy();
                }
            }
        }
    }

    readonly property var matraOf: ({
        "आ": "ा", "इ": "ि", "ई": "ी", "उ": "ु", "ऊ": "ू", "ऋ": "ृ",
        "ए": "े", "ऐ": "ै", "ओ": "ो", "औ": "ौ", "ऍ": "ॅ", "ऑ": "ॉ"
    })
    function isConsonant(c) {
        const cp = c.codePointAt(0);
        return (cp >= 0x0915 && cp <= 0x0939) || (cp >= 0x0958 && cp <= 0x095F) || c === "ळ" || c === "ऱ";
    }

    // a tablet or a phone: the keyboard comes up with a text field of the shell
    // and goes with it (a short wait: focus moving between two fields is not a
    // leaving); one opened by hand stays
    property bool autoShown: false
    Connections {
        target: Ui
        function onTextFocusChanged() { textFocusSettle.restart(); }
    }
    Connections {
        target: FormFactor
        function onFocusedChanged() { textFocusSettle.restart(); }
    }
    Timer {
        id: textFocusSettle
        interval: 200
        onTriggered: {
            const touchFirst = ["tablet", "phone"].indexOf(FormFactor.focused.profile) >= 0;
            // a text field reached with a game controller: there is no keyboard in the hand
            // (moved onto it - a field a surface focuses by itself, the launcher's search, is not)
            const padFirst = GamepadNav.recent() && Ui.textByKeys;
            if (Ui.textFocus && (touchFirst || padFirst) && !root.shown && !Lock.locked) {
                root.shown = true; root.typed = ""; root.padDriven = padFirst && !touchFirst; root.remote = false;
                root.autoShown = true;
            } else if ((!Ui.textFocus || !(touchFirst || padFirst)) && root.autoShown) {
                root.shown = false; root.autoShown = false;
            }
        }
    }
    onShownChanged: if (!shown) autoShown = false

    function toggle() {
        // opened with keys (a remote's OK on the Quick Settings tile, the
        // launcher's action): typed from the remote
        if (!shown && Ui.keysActivated) {
            openRemote();
            return;
        }
        shown = !shown;
        typed = "";
        dismissedWord = "";
        padDriven = false;
        remote = false;
    }

    // Remote mode, a TV's full-width keyboard: the keyboard takes the keys
    // (arrows move, OK types the key, Back cancels), what is typed collects
    // on its own line, and Done hands it to the app that had the focus. A
    // remote cannot type into the app while the keyboard listens to it, so
    // the text goes over in one piece when the keyboard lets go.
    property bool remote: false
    property string draft: ""
    function openRemote() {
        if (Lock.locked)
            return;                          // the lock screen has its own keyboard
        draft = "";
        typed = "";
        dismissedWord = "";
        remote = true;
        padDriven = true;
        shown = true;
    }
    function cancelRemote() {
        remote = false;
        shown = false;
        draft = "";
    }
    property string lastCommitted: ""        // for the tests
    function commit() {
        const text = draft;
        remote = false;
        shown = false;
        draft = "";
        lastCommitted = text;
        if (text !== "")
            commitLater.text = text, commitLater.restart();
    }
    Timer {
        // the keyboard lets go of the keys first and the compositor hands them
        // back to the field (measured: 180 ms was too soon for the launcher)
        id: commitLater
        property string text: ""
        interval: 450
        onTriggered: Quickshell.execDetached(["wtype", "--", text])
    }
    Connections { target: Ui; function onTypingRequested() { root.openRemote(); } }

    // A controller drives the keys (Services/GamepadNav and Services/InputPlumber
    // send what the pad did while the keyboard is open): the d-pad moves a
    // highlighted key, A taps it, and the rest are Steam's keyboard's buttons -
    // X Backspace, Y space, Start Enter, Select Shift, B hides it. The cursor
    // shows only once a controller is used, so touch looks as it always did.
    property bool padDriven: false
    signal padMove(string direction)        // up, down, left, right (Modules/Osk/Keyboard)
    signal padTap()
    property string lastPad: ""             // for the tests
    property string cursorLabel: ""         // the key under the cursor (Modules/Osk/Keyboard)
    function pad(action) {
        lastPad = action;
        padDriven = true;
        if (action === "up" || action === "down" || action === "left" || action === "right")
            padMove(action);
        else if (action === "press")
            padTap();
        else if (action === "backspace")
            press("BackSpace");
        else if (action === "space")
            press("space");
        else if (action === "enter")
            press("Return");
        else if (action === "shift")
            shift = !shift;
        else if (action === "close")
            remote ? cancelRemote() : toggle();
    }
    function nextLanguage() {
        langIndex = (langIndex + 1) % languages.length;
        page = "letters";
        shift = false;
    }

    // one tap: text, or a named key (BackSpace, Return, Tab, space)
    function press(key) {
        const named = ["BackSpace", "Return", "Tab", "Left", "Right", "Up", "Down", "Delete", "Escape", "Home", "End"];
        // Ctrl / Alt armed: the key with them held (a letter, a digit, or a named key)
        if ((ctrl || alt) && (named.indexOf(key) >= 0 || /^[a-z0-9]$/i.test(key))) {
            Quickshell.execDetached(["wtype"].concat(modArgs(true), ["-k", key.length === 1 ? key.toLowerCase() : key], modArgs(false)));
            used();
            return;
        }
        if (remote) {                         // the draft, not the app
            if (key === "BackSpace")
                draft = draft.slice(0, -1);
            else if (key === "Return")
                commit();
            else if (named.indexOf(key) < 0) {
                let ch = key === "space" ? " " : key;
                if (lang === "mr" && matraOf[ch] !== undefined && draft.length > 0 && isConsonant(draft.slice(-1)))
                    ch = matraOf[ch];
                draft += ch;
                shift = false;
            }
            typed = draft.slice(-16);
            return;
        }
        if (named.indexOf(key) >= 0) {
            Quickshell.execDetached(["wtype", "-k", key]);
            typed = key === "BackSpace" ? typed.slice(0, -1) : "";
            return;
        }
        let out = key === "space" ? " " : key;
        // smart matras on the hand-made Devanagari layout only: xkb's Indic
        // layouts (InScript …) have matra keys of their own
        if (lang === "mr" && matraOf[out] !== undefined && typed.length > 0 && isConsonant(typed.slice(-1)))
            out = matraOf[out];
        shift = false;
        Quickshell.execDetached(["wtype", "--", out]);
        typed = (typed + out).slice(-16);
    }
}
