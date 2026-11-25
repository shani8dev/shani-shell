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
import "../Common/ToolPath.js" as ToolPath

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
            property string hand: "center"       // center | left | right
            property bool autocorrect: true
            property bool autoCaps: true         // a capital to start a sentence; ". " on two spaces
        }
    }
    property string size: prefs.size === "compact" ? "compact" : "fixed"
    // a persisted hand preference; anything on disk we do not know is centered
    property string hand: prefs.hand === "left" || prefs.hand === "right" ? prefs.hand : "center"
    property real panelOpacity: {
        const v = Number(prefs.panelOpacity);
        return v >= 0.55 && v <= 1 ? v : 1;
    }
    property bool suggestions: prefs.suggestions !== false
    property bool autocorrect: prefs.autocorrect !== false
    property bool autoCaps: prefs.autoCaps !== false
    readonly property bool compact: size === "compact"
    function savePrefs() {
        prefs.size = root.size;
        prefs.panelOpacity = root.panelOpacity;
        prefs.suggestions = root.suggestions;
        prefs.hand = root.hand;
        prefs.autocorrect = root.autocorrect;
        prefs.autoCaps = root.autoCaps;
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
    function toggleAutocorrect() { root.autocorrect = !root.autocorrect; savePrefs(); }
    function toggleAutoCaps() { root.autoCaps = !root.autoCaps; savePrefs(); }
    function cycleHand() {
        const sides = ["center", "left", "right"];
        root.hand = sides[(sides.indexOf(root.hand) + 1) % sides.length];
        savePrefs();
    }

    // ---- paste and held-key repeat ------------------------------------------
    // paste never goes through a shell: the clipboard is one argv element, so
    // quotes, $() and newlines in it are typed, never interpreted.
    function paste() {
        const text = String(Quickshell.clipboardText || "");
        if (text === "" || Lock.locked)
            return;
        if (remote) {                         // the draft, not the app
            draft += text;
            typed = draft.slice(-16);
            return;
        }
        Quickshell.execDetached(["wtype", "--", text]);
        typed = (typed + text).slice(-16);
    }

    // repeat is input, not motion: it ignores reduceMotion and its timers are
    // stopped whenever no key is held, so an idle keyboard runs nothing.
    readonly property int repeatDelay: 400
    readonly property int repeatInterval: 80
    property string repeatKey: ""
    function startRepeat(key) {
        if (!key || Lock.locked)
            return;
        repeatKey = key;
        repeatDelayTimer.restart();
    }
    function stopRepeat() {
        repeatKey = "";
        repeatDelayTimer.stop();
        repeatTick.stop();
    }
    Timer {
        id: repeatDelayTimer
        interval: root.repeatDelay
        onTriggered: {
            if (root.repeatKey === "")
                return;
            root.press(root.repeatKey);
            repeatTick.restart();
        }
    }
    Timer {
        id: repeatTick
        interval: root.repeatInterval
        repeat: true
        onTriggered: if (root.repeatKey !== "") root.press(root.repeatKey)
    }

    // handwriting: rows of strokes read on this machine (Tesseract), typed in order
    readonly property string writeTool: ToolPath.of(Quickshell.env("SHANI_HANDWRITING_TOOL"), "handwriting.py")
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

    // ---- the word engine (SwiftKey's prediction bar, on this machine) --------
    // bridge/osk-predict.py: completion, the next word, autocorrect, swipe and
    // learning from what is typed - one process while the keyboard is up and
    // suggestions are on, nothing while it is hidden. Nothing typed into a
    // password field is sent to it, so it never learns a secret.
    readonly property string predictTool: ToolPath.of(Quickshell.env("SHANI_OSK_PREDICT_TOOL"), "osk-predict.py")
    property string context: ""             // the last words typed, for the next-word guess
    property var predicted: []              // the engine's words for `predictedFor`
    property string predictedFor: "\u0000"
    property string correction: ""          // what a space would turn the word into
    property var swiped: []                 // the other words a swipe could have been
    property var undoable: null             // { from, to }: Backspace right after an autocorrect undoes it
    readonly property bool secret: Ui.promptKeyboard || (Ui.textInput !== null && Ui.textInput.echoMode !== TextInput.Normal)
    // the engine works for any language with a system dictionary (hunspell);
    // capitals and ". " only where the script has them
    readonly property bool latin: lang === "en" || (isXkb && /^(us|gb|fr|de|es|it|pt|nl|se|no|dk|fi|pl|cz|tr|in\+eng)/.test(lang))
    readonly property bool engineUp: engine.running
    Process {
        id: engine
        command: ["python3", root.predictTool]
        running: root.shown && root.suggestions
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let r;
                try { r = JSON.parse(line); } catch (e) { return; }
                if (r.op === "suggest") {
                    root.predicted = r.words || [];
                    root.predictedFor = r.word || "";
                    root.correction = root.autocorrect && r.correction ? r.correction : "";
                } else if (r.op === "swipe") {
                    root.typeSwiped(r.words || []);
                }
            }
        }
    }
    function ask(req) {
        if (!engine.running || root.secret) return;
        req.lang = root.lang;
        engine.write(JSON.stringify(req) + "\n");
    }
    Timer { id: askSoon; interval: 40; onTriggered: root.ask({ op: "suggest", prev: root.context.replace(/[A-Za-z']*$/, ""), word: root.currentWord() }) }
    function learnWord() {
        // the last two words, so the engine learns the pair as well as the word
        const words = root.context.trim().split(/\s+/).slice(-2).join(" ");
        if (words !== "") root.ask({ op: "learn", text: words });
    }
    function forgetLearned() { if (engine.running) engine.write(JSON.stringify({ op: "forget" }) + "\n"); }
    function noteTyped(out) {
        root.context = (root.context + out).slice(-80);
        askSoon.restart();
    }
    // ---- swipe: the keys a finger passed over, decoded into a word ---------
    property string swipeFirst: ""          // the letter the press already typed
    function swipe(keys) {
        if (!engine.running || root.secret || keys.length < 2) return false;
        root.swipeFirst = keys.charAt(0);
        root.ask({ op: "swipe", prev: root.context, keys: keys });
        return true;
    }
    function typeSwiped(words) {
        if (!words.length) { root.swipeFirst = ""; return; }
        // the press typed the first letter; the word replaces it, then a space
        const args = ["wtype"];
        if (root.swipeFirst !== "") args.push("-k", "BackSpace");
        const word = root.shift ? words[0].charAt(0).toUpperCase() + words[0].slice(1) : words[0];
        args.push("--", word + " ");
        Quickshell.execDetached(args);
        root.typed = (root.typed.slice(0, root.typed.length - (root.swipeFirst ? 1 : 0)) + word + " ").slice(-16);
        root.context = (root.context.slice(0, root.context.length - (root.swipeFirst ? 1 : 0)) + word + " ").slice(-80);
        root.swiped = words.slice(1);
        root.lastSwiped = word;
        root.swipeFirst = "";
        if (!root.capsLock) root.shift = false;
        root.learnWord();
        root.capitalise();
        askSoon.restart();
    }

    property string lastSwiped: ""
    // a different word from the swipe's list, in place of the one it typed
    function replaceSwiped(word) {
        if (root.lastSwiped === "") return;
        const args = ["wtype"];
        for (let i = 0; i < root.lastSwiped.length + 1; i++) args.push("-k", "BackSpace");
        args.push("--", word + " ");
        Quickshell.execDetached(args);
        root.context = (root.context.slice(0, root.context.length - root.lastSwiped.length - 1) + word + " ").slice(-80);
        root.typed = root.context.slice(-16);
        root.lastSwiped = "";
        root.swiped = [];
        root.learnWord();
    }
    // the word as typed, not its correction: a space, and the word is learned
    // (a name, a new word) so it is not corrected again
    function keepTyped() {
        root.dismissedWord = root.currentWord();
        root.correction = "";
        Quickshell.execDetached(["wtype", "--", " "]);
        root.typed = (root.typed + " ").slice(-16);
        root.noteTyped(" ");
        root.learnWord();
    }
    // a held key's alternate in place of the letter the press typed
    function replaceLast(ch) {
        Quickshell.execDetached(["wtype", "-k", "BackSpace", "--", ch]);
        root.typed = (root.typed.slice(0, -1) + ch).slice(-16);
        if (!root.secret) { root.context = (root.context.slice(0, -1) + ch).slice(-80); askSoon.restart(); }
    }
    // text from the clipboard panel's pins (or anything whole), typed as it is
    function typeText(t) {
        if (!t) return;
        Quickshell.execDetached(["wtype", "--", t]);
        root.typed = (root.typed + t).slice(-16);
        if (!root.secret) root.context = (root.context + t).slice(-80);
    }

    // ---- capitals, as a phone keyboard does them ---------------------------
    property bool capsLock: false
    property double lastShiftTap: 0
    function tapShift() {
        const now = Date.now();
        if (root.capsLock) { root.capsLock = false; root.shift = false; }
        else if (root.shift && now - root.lastShiftTap < 400) root.capsLock = true;   // two quick taps: caps lock
        else root.shift = !root.shift;
        root.lastShiftTap = now;
    }
    // the start of a field or a sentence takes a capital
    function capitalise() {
        if (root.autoCaps && root.latin && !root.secret && root.page === "letters"
                && (root.context === "" || /[.!?]\s+$/.test(root.context)))
            root.shift = true;
    }

    // ---- word suggestions --------------------------------------------------
    // The fallback when the engine is not running: a bounded, built-in list of
    // common English words, for the English layout only.
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
        // a word in any script: what follows the last space or punctuation
        const m = String(typed).match(/[^\s.,!?;:"()\[\]{}<>\/\\0-9]+$/);
        return m ? m[0].toLowerCase() : "";
    }
    function suggestionsFor(word) {
        const w = String(word || "").toLowerCase();
        if (root.engineUp && root.predictedFor === w)
            return root.predicted.slice(0, 3);
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
        root.context = (root.context.slice(0, root.context.length - w.length) + word + " ").slice(-80);
        root.correction = "";
        if (!root.capsLock) shift = false;
        root.learnWord();
        askSoon.restart();
    }

    // Layouts: "en" and "mr" are drawn by hand (mr with smart matras); any
    // other entry is an xkb layout id ("in+tam", "ru", "ara" …), generated
    // from the system's xkb data by osk-layout.py and cached here.
    property var xkb: ({})                  // id -> { name, rows: [[{n, s}]] }
    readonly property bool isXkb: lang !== "en" && lang !== "mr"
    readonly property var current: isXkb ? (xkb[lang] || null) : null
    readonly property string script: ToolPath.of(Quickshell.env("SHANI_OSK_LAYOUT_TOOL"), "osk-layout.py")

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
    // up: a fresh sentence (a capital first); down: nothing runs
    onShownChanged: {
        if (!shown) { autoShown = false; root.stopRepeat(); return; }
        root.context = "";
        root.swiped = [];
        root.capitalise();
    }
    onRemoteChanged: if (remote) root.stopRepeat()

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
        // Backspace right after an autocorrect puts back what was typed
        if (key === "BackSpace" && root.undoable) {
            const u = root.undoable;
            root.undoable = null;
            const args = ["wtype"];
            for (let i = 0; i < u.to.length + 1; i++) args.push("-k", "BackSpace");
            args.push("--", u.from);
            Quickshell.execDetached(args);
            root.context = (root.context.slice(0, root.context.length - u.to.length - 1) + u.from).slice(-80);
            root.typed = root.context.slice(-16);
            root.correction = "";
            root.dismissedWord = u.from;          // kept as typed: the next space leaves it alone
            return;
        }
        root.undoable = null;
        root.swiped = [];
        if (named.indexOf(key) >= 0) {
            Quickshell.execDetached(["wtype", "-k", key]);
            typed = key === "BackSpace" ? typed.slice(0, -1) : "";
            if (key === "BackSpace") root.context = root.context.slice(0, -1);
            else if (key === "Return") { root.learnWord(); root.context = ""; }
            else root.context = "";
            askSoon.restart();
            if (key === "Return") root.capitalise();
            return;
        }
        if (key === "space" && root.latin && !root.secret) {
            const w = root.currentWord();
            // the word becomes its correction, as the space is typed (undone by Backspace)
            if (root.autocorrect && w !== "" && root.correction !== "" && root.correction !== w.toLowerCase()
                    && root.predictedFor === w.toLowerCase() && root.dismissedWord !== w) {
                let fix = root.correction;
                if (/^[A-Z]/.test(w)) fix = fix.charAt(0).toUpperCase() + fix.slice(1);
                const args = ["wtype"];
                for (let i = 0; i < w.length; i++) args.push("-k", "BackSpace");
                args.push("--", fix + " ");
                Quickshell.execDetached(args);
                root.context = (root.context.slice(0, root.context.length - w.length) + fix + " ").slice(-80);
                root.typed = root.context.slice(-16);
                root.undoable = { from: w, to: fix };
                root.correction = "";
                root.learnWord();
                root.capitalise();
                askSoon.restart();
                return;
            }
            // two spaces after a word: a full stop, as phones do
            if (root.autoCaps && /[A-Za-z0-9]\s$/.test(root.context) && !/[.!?]\s$/.test(root.context)) {
                Quickshell.execDetached(["wtype", "-k", "BackSpace", "--", ". "]);
                root.context = (root.context.slice(0, -1) + ". ").slice(-80);
                root.typed = root.context.slice(-16);
                root.capitalise();
                askSoon.restart();
                return;
            }
        }
        let out = key === "space" ? " " : key;
        // smart matras on the hand-made Devanagari layout only: xkb's Indic
        // layouts (InScript …) have matra keys of their own
        if (lang === "mr" && matraOf[out] !== undefined && typed.length > 0 && isConsonant(typed.slice(-1)))
            out = matraOf[out];
        if (!root.capsLock) shift = false;
        Quickshell.execDetached(["wtype", "--", out]);
        typed = (typed + out).slice(-16);
        if (root.secret) return;                 // nothing from a password field is kept or sent
        root.noteTyped(out);
        if (out === " ") { root.learnWord(); root.capitalise(); }
    }
}
