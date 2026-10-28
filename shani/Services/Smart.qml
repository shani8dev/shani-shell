pragma Singleton
// The smart Island's suggestions (after Android's smart text selection): when
// something is copied, one useful next step — open a link, write an email,
// call a number, translate a foreign script, ask Chronoa about an error, see a
// colour. It stays ten seconds and never acts without a click.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var suggestion: null        // { icon, text, run }

    function classify(t) {
        t = (t || "").trim();
        if (t === "" || t.length > 4000)
            return null;
        const one = t.split("\n")[0].slice(0, 60);
        if (/^https?:\/\/\S+$/.test(t))
            return { icon: "web-browser", text: "Open " + t.replace(/^https?:\/\//, "").slice(0, 40), run: () => Qt.openUrlExternally(t) };
        if (/^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(t))
            return { icon: "mail-unread", text: "Email " + t, run: () => Qt.openUrlExternally("mailto:" + t) };
        if (/^\+?[\d][\d\s-]{7,15}\d$/.test(t))
            return { icon: "call-start", text: "Call " + t, run: () => Chronoa.ask("Call " + t) };
        if (/^#?[0-9a-f]{6}$/i.test(t))
            return { icon: "color-select", text: "Colour #" + t.replace("#", ""), color: "#" + t.replace("#", ""), run: () => {} };
        if (/(Traceback|Exception|Error:|error\[|FAILED|panicked at|Segmentation fault)/.test(t))
            return { icon: "dialog-question", text: "Ask Chronoa to explain this error", run: () => Chronoa.ask("Explain this error and how to fix it:\n" + t) };
        // mostly a non-Latin script: offer a translation
        const letters = t.replace(/[\s\d\p{P}\p{S}]/gu, "");
        const latin = (letters.match(/[A-Za-zÀ-ɏ]/g) || []).length;
        if (letters.length >= 4 && latin / letters.length < 0.3)
            return { icon: "preferences-desktop-locale", text: "Translate “" + one + "”", run: () => Qt.openUrlExternally("https://translate.google.com/?sl=auto&tl=en&op=translate&text=" + encodeURIComponent(t.slice(0, 2000))) };
        return null;
    }

    // every copy, from any app: Quickshell's own clipboardText only changes
    // while one of its windows has focus. One line per copy, its own newlines
    // turned into U+001F; the first is what was on the clipboard already.
    readonly property double startedAt: Date.now()
    property string lastText: ""
    Process {
        running: true
        command: ["wl-paste", "--no-newline", "--type", "text", "--watch", "sh", "-c", "head -c 4000 | tr '\\n' '\\037'; echo"]
        stdout: SplitParser {
            onRead: line => {
                // the same text again is not a new copy: wl-clip-persist takes
                // the clipboard over after each one, announcing it a second time
                const t = line.split("\u001f").join("\n");
                if (t === root.lastText)
                    return;
                root.lastText = t;
                // what was on the clipboard already, announced as the watch starts
                // (nothing is announced when it starts empty, so: by time, not count)
                if (Date.now() - root.startedAt < 1500)
                    return;
                const s = root.classify(t);
                if (s) {
                    root.suggestion = s;
                    expire.restart();
                }
            }
        }
    }
    Timer { id: expire; interval: 10000; onTriggered: root.suggestion = null }
}
