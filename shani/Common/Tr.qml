pragma Singleton
// The shell's words in the person's language. Quickshell installs no Qt
// translator, so qsTr() would translate nothing; this is the small stand-in:
// i18n/<lang>.json maps the English text to the translation, and
// Tr.t("English") answers with it, or the English when there is none. %1, %2…
// are filled from the arguments, after translating, so word order can change.
//
// The language is the one chosen in Settings > Date & language (locale.conf,
// followed live), else the session's (LC_ALL, LC_MESSAGES, LANG);
// SHANI_SHELL_LANG overrides both (the tests).
// What the catalog lacks is translated on this machine by Chronoa's local model
// (bridge/translate.py, cached) when Settings > Date & language allows it -
// never by a web service. Off by default: measured with Qwen3-8B, about a
// third of short labels came back wrong ("Do Not Disturb" as "make
// unprofessional"), so the reviewed catalog is the real source. tools/i18n.py lists the strings and the gaps.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    // ~/.config/locale.conf (Settings > Date & language writes it): followed
    // live, so the shell's own words change at once; apps at the next login
    property string chosen: ""
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/locale.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { const m = /^LANG=(\S+)/m.exec(text()); root.chosen = m ? m[1] : ""; }
        onLoadFailed: root.chosen = ""
    }
    readonly property string lang: {
        const forced = Quickshell.env("SHANI_SHELL_LANG");
        if (forced)
            return forced.slice(0, 2).toLowerCase();
        if (root.chosen && root.chosen !== "C" && root.chosen !== "POSIX")
            return root.chosen.slice(0, 2).toLowerCase();
        for (const v of ["LC_ALL", "LC_MESSAGES", "LANG"]) {
            const x = Quickshell.env(v);
            if (x && x !== "C" && x !== "POSIX")
                return x.slice(0, 2).toLowerCase();
        }
        return "en";
    }
    property var reviewed: ({})         // shani/i18n/<lang>.json, checked by a person
    property var machine: ({})          // ~/.cache/shani-shell/i18n/<lang>.json, Chronoa's local model
    readonly property var table: Object.assign({}, machine, reviewed)
    // what is shown without a translation, gathered while drawing and handed to
    // bridge/translate.py in one go (a plain object: no binding depends on it)
    readonly property var pending: ({})
    readonly property bool machineOn: lang !== "en" && Settings.data.machineTranslate
    function t(s, ...args) {
        let out = root.table[s];
        if (out === undefined) {
            out = s;
            if (root.machineOn && root.loaded && !root.pending[s]) {
                root.pending[s] = true;
                ask.restart();
            }
        }
        args.forEach((a, i) => out = out.replace("%" + (i + 1), a));
        return out;
    }
    property bool loaded: false         // both files read: only then is a miss a real one
    property int asked: 0               // strings handed to the model (the tests)
    FileView {
        path: root.lang === "en" ? "" : decodeURIComponent(Qt.resolvedUrl("../i18n/" + root.lang + ".json").toString().replace(/^file:\/\//, ""))
        printErrors: false
        onLoaded: { try { root.reviewed = JSON.parse(text()); } catch (e) { root.reviewed = {}; } settle.restart(); }
        onLoadFailed: { root.reviewed = {}; settle.restart(); }
    }
    FileView {
        id: cacheFile
        path: root.lang === "en" ? "" : (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/shani-shell/i18n/" + root.lang + ".json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.machine = JSON.parse(text()); } catch (e) {} }
    }
    Timer { id: settle; interval: 1500; onTriggered: root.loaded = true }
    // a quiet moment after the last miss, then one batch
    Timer {
        id: ask
        interval: 2500
        onTriggered: {
            if (translator.running) { restart(); return; }
            const list = Object.keys(root.pending).filter(k => root.table[k] === undefined);
            if (list.length === 0) return;
            root.asked += list.length;
            translator.payload = JSON.stringify(list);
            translator.running = true;
        }
    }
    Process {
        id: translator
        property string payload: ""
        command: ["python3", Quickshell.env("SHANI_TRANSLATE_TOOL") || "/usr/lib/shani-shell/translate.py", "strings", root.lang]
        stdinEnabled: true
        onStarted: { write(payload); stdinEnabled = false; }
        onExited: { stdinEnabled = true; cacheFile.reload(); }
    }
}
