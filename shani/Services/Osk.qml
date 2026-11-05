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

    function toggle() {
        shown = !shown;
        typed = "";
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
