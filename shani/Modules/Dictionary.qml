// The Dictionary (Modules/Dictionary.qml): an offline dictionary + thesaurus
// over the word list bundled at the bottom of this file — every entry has
// definitions, synonyms and antonyms. Search is local: case-insensitive
// substring over the bundled words, no network. Opening the window with
// something on the clipboard pre-fills the search box (the selection Lens's
// Search puts there, or any word copied in the shell). Terms searched are
// remembered, newest first, capped at 20, with a Clear action; clicking a
// result or a history row shows its definitions, synonyms and antonyms.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common

AppWindow {
    id: win
    appName: "Dictionary"
    visible: Ui.dictionary
    onGone: Ui.dictionary = false
    margins: 0
    implicitWidth: Theme.px(520)
    implicitHeight: Theme.px(640)

    // ---- the local word list: { word, definitions, synonyms, antonyms } ----
    readonly property var entries: [
        { word: "help", definitions: [Tr.t("Assist or support someone"), Tr.t("A person or thing that provides aid")], synonyms: [Tr.t("aid"), Tr.t("assistance"), Tr.t("support")], antonyms: [Tr.t("hinder"), Tr.t("obstruct")] },
        { word: "help", definitions: [Tr.t("Assist or support someone"), Tr.t("A person or thing that provides aid")], synonyms: [Tr.t("aid"), Tr.t("assistance"), Tr.t("support")], antonyms: [Tr.t("hinder"), Tr.t("obstruct")] },
        { word: "value", definitions: [Tr.t("The worth, importance or usefulness of something")], synonyms: [Tr.t("worth"), Tr.t("importance"), Tr.t("merit")], antonyms: [Tr.t("worthlessness")] },
        { word: "search", definitions: [Tr.t("Look for something carefully"), Tr.t("Investigate or seek")], synonyms: [Tr.t("look for"), Tr.t("seek"), Tr.t("find")], antonyms: [Tr.t("ignore")] },
        { word: "word", definitions: [Tr.t("A single distinct element of speech"), Tr.t("A command or promise")], synonyms: [Tr.t("term"), Tr.t("phrase")], antonyms: [Tr.t("silence")] },
        { word: "file", definitions: [Tr.t("A set of related data or papers kept together")], synonyms: [Tr.t("record"), Tr.t("document")], antonyms: [Tr.t("destroy")] },
        { word: "list", definitions: [Tr.t("A number of connected items")], synonyms: [Tr.t("catalogue"), Tr.t("register")], antonyms: [Tr.t("forget")] },
        { word: "result", definitions: [Tr.t("Something that happens or is obtained"), Tr.t("A conclusion reached after a calculation")], synonyms: [Tr.t("outcome"), Tr.t("answer")], antonyms: [Tr.t("failure")] },
        { word: "time", definitions: [Tr.t("A point or period during which something takes place")], synonyms: [Tr.t("moment"), Tr.t("occasion")], antonyms: [Tr.t("end")] },
        { word: "work", definitions: [Tr.t("Activity involving effort and skill"), Tr.t("A job or task")], synonyms: [Tr.t("job"), Tr.t("task")], antonyms: [Tr.t("rest")] },
        { word: "edit", definitions: [Tr.t("Change or correct something written or recorded")], synonyms: [Tr.t("revise"), Tr.t("revise")], antonyms: [Tr.t("finalise")] },
        { word: "person", definitions: [Tr.t("A human being"), Tr.t("A person in a given role")], synonyms: [Tr.t("human"), Tr.t("individual")], antonyms: [Tr.t("entity")] },
        { word: "color", definitions: [Tr.t("A colour of paint, light or dye")], synonyms: [Tr.t("hue"), Tr.t("tone")], antonyms: [Tr.t("grey")] },
        { word: "notice", definitions: [Tr.t("Become aware of something"), Tr.t("An announcement of something coming")], synonyms: [Tr.t("see"), Tr.t("learn")], antonyms: [Tr.t("miss")] }
    ]

    // ---- search and results -------------------------------------------------
    property string query: ""
    readonly property string q: win.query.trim().toLowerCase()
    readonly property var results: win.entries.filter(e => e.word.toLowerCase().indexOf(win.q) >= 0)
    readonly property string entryWord: win.q === "" ? "" : (win.results.length === 1 ? win.results[0].word : "")
    readonly property var entry: win.entryWord !== "" ? win.entries.find(e => e.word === win.entryWord) : null
    readonly property bool hasQuery: win.q !== ""
    readonly property bool noMatch: win.hasQuery && win.results.length === 0 && win.entry === null

    // ---- history of searched terms, newest first, capped at 20 --------------
    property var history: []

    function search() {
        const q = win.query.trim();
        if (q !== "") {
            if (win.history.indexOf(q) >= 0)
                win.history.splice(win.history.indexOf(q), 1);
            win.history.unshift(q);
            win.history = win.history.slice(0, 20);
        }
    }
    function recall(w) { win.query = w; win.search(); }

    // ---- pinned words, kept across runs in the shell's state dir ------------
    property var pinned: []
    readonly property bool isPinned: win.entryWord !== "" && win.pinned.indexOf(win.entryWord) >= 0

    FileView {
        id: pinnedFile
        path: Quickshell.statePath("dictionary-pinned.json")
        printErrors: false
        onLoaded: { try { win.pinned = JSON.parse(text()); } catch (e) {} }
    }
    function savePinned() { pinnedFile.setText(JSON.stringify(win.pinned)); }
    function togglePin() {
        if (win.entryWord === "") return;
        const list = win.pinned.slice();
        const i = list.indexOf(win.entryWord);
        if (i >= 0) list.splice(i, 1);
        else list.unshift(win.entryWord);
        win.pinned = list;
        win.savePinned();
    }
    function unpin(w) {
        const list = win.pinned.slice();
        const i = list.indexOf(w);
        if (i >= 0) { list.splice(i, 1); win.pinned = list; win.savePinned(); }
    }

    // Hand the word back to the keyboard. The Dictionary window and the OSK are
    // separate surfaces with no shared signal, so the clipboard is the only
    // channel: copy the entry here, close so the field is in front again, and
    // the OSK's existing Paste key inserts it (remote mode: its draft).
    function typeIntoField() {
        const word = win.entryWord;
        if (word === "") return;
        Quickshell.clipboardText = word;
        Ui.dictionary = false;
    }

    // ---- near misses: prefix/substring hints when nothing matched -----------
    function suggestFor(word) {
        const w = word.toLowerCase(), q = win.q;
        if (q.length === 0) return false;
        const stem = q.slice(0, Math.min(2, q.length));
        return w.indexOf(stem) >= 0 || w.indexOf(q.charAt(0)) === 0;
    }
    readonly property var suggestions: win.noMatch
        ? win.entries.filter(e => win.suggestFor(e.word)).slice(0, 6)
        : []

    // opening the window with the word Lens, the editor or Translate left on
    // the clipboard pre-fills the box when it is empty; the non-empty query is
    // what makes the seed one-shot. The clipboard itself is never cleared —
    // it belongs to the person, not to this window.
    onVisibleChanged: {
        const seed = String(Quickshell.clipboardText || "").trim();
        if (visible && win.query === "" && seed !== "")
            win.query = seed;
    }

    Item {
        id: body
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: win.requestClose()
    }

    body {
        ColumnLayout {
            id: col
            anchors.fill: body
            anchors.margins: Theme.px(14)
            spacing: Theme.px(10)

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                TextField {
                    id: searchBox
                    Layout.fillWidth: true
                    placeholder: Tr.t("Type a word…")
                    Accessible.name: Tr.t("Search a word")
                    Accessible.description: Tr.t("Dictionary and thesaurus search, offline")
                    onAccepted: win.search()
                }
                Button { text: Tr.t("Search"); kind: "primary"; onClicked: win.search() }
            }

            Text {
                visible: win.hasQuery && win.results.length > 0
                text: Tr.t("Definitions, synonyms and antonyms")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }

            Text {
                visible: win.noMatch
                text: Tr.t("No definitions for ") + win.q
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
            }

            // ---- near misses: a hint from the bundled words ------------------
            ColumnLayout {
                visible: win.noMatch && win.suggestions.length > 0
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text { Layout.fillWidth: true; text: Tr.t("Did you mean"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold; Accessible.name: Tr.t("Did you mean") }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: win.suggestions
                        Button {
                            required property var modelData
                            flat: true
                            text: modelData.word
                            Accessible.name: Tr.t("Did you mean ") + modelData.word
                            onClicked: win.recall(modelData.word)
                        }
                    }
                }
            }

            Text {
                visible: !win.hasQuery && win.history.length === 0
                text: Tr.t("Type a word to start · see definitions, synonyms and antonyms")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }

            // ---- the detail of the word found / chosen ----------------------
            ColumnLayout {
                id: detail
                visible: win.entry !== null
                Layout.fillWidth: true
                spacing: Theme.px(8)

                Text {
                    visible: win.entry !== null
                    Layout.fillWidth: true
                    text: win.entry ? win.entry.word : ""
                    font.family: Theme.font
                    font.pixelSize: Theme.px(17) * Theme.fontScale
                    font.weight: Font.Bold
                    Accessible.name: Tr.t("Word")
                }

                Button {
                    flat: true
                    visible: win.entryWord !== ""
                    text: win.isPinned ? Tr.t("Unpin word") : Tr.t("Pin word")
                    Accessible.name: text
                    onClicked: win.togglePin()
                }

                // copies the entry to the clipboard for the OSK's Paste key
                Button {
                    flat: true
                    visible: win.entryWord !== ""
                    text: Tr.t("Type into field")
                    Accessible.name: text
                    onClicked: win.typeIntoField()
                }

                Repeater {
                    model: win.entry ? win.entry.definitions : []
                    ListRow {
                        required property string modelData
                        Layout.fillWidth: true
                        icon: "view-list-details"
                        title: modelData
                        interactive: false
                    }
                }

                Text { Layout.fillWidth: true; text: Tr.t("Synonyms"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold }
                Repeater {
                    model: win.entry ? win.entry.synonyms : []
                    ListRow { required property string modelData; Layout.fillWidth: true; title: modelData; interactive: false }
                }

                Text { Layout.fillWidth: true; text: Tr.t("Antonyms"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold }
                Repeater {
                    model: win.entry ? win.entry.antonyms : []
                    ListRow { required property string modelData; Layout.fillWidth: true; title: modelData; interactive: false }
                }
            }

            // ---- the results while more than one word matches ---------------
            ColumnLayout {
                visible: win.hasQuery && win.results.length > 1 && win.entry === null
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text { Layout.fillWidth: true; text: Tr.t("Results"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold }
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(220, col.implicitHeight)
                    Layout.minimumHeight: Theme.px(24)
                    contentHeight: winCol.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: winCol
                        width: parent.width
                        spacing: Theme.px(2)
                        Repeater {
                            model: win.results
                            ListRow {
                                required property var modelData
                                Layout.fillWidth: true
                                icon: "text-x-generic"
                                title: modelData.word
                                subtitle: modelData.definitions.length > 0 ? modelData.definitions[0] : ""
                                onClicked: { win.query = modelData.word; win.search(); }
                            }
                        }
                    }
                }
            }

            // ---- history of searched terms, newest first ---------------------
            ColumnLayout {
                visible: win.history.length > 0
                Layout.fillWidth: true
                spacing: Theme.px(4)
                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: Tr.t("History"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold }
                    Button { text: Tr.t("Clear"); kind: "plain"; onClicked: win.history = [] }
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(110, histCol.implicitHeight + 4)
                    Layout.minimumHeight: Theme.px(24)
                    contentHeight: histCol.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: histCol
                        width: parent.width
                        spacing: Theme.px(2)
                        Repeater {
                            model: win.history
                            ListRow {
                                required property string modelData
                                Layout.fillWidth: true
                                icon: "text-x-generic"
                                title: modelData
                                onClicked: win.recall(modelData)
                            }
                        }
                    }
                }
            }

            // ---- pinned words, newest first, with an empty state -------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text { Layout.fillWidth: true; text: Tr.t("Pinned"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; font.weight: Font.DemiBold; Accessible.name: Tr.t("Pinned words") }
                Text {
                    visible: win.pinned.length === 0
                    Layout.fillWidth: true
                    text: Tr.t("No pinned words yet · pin one from its entry")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Flow {
                    visible: win.pinned.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: win.pinned
                        Button {
                            required property string modelData
                            flat: true
                            text: modelData
                            Accessible.name: Tr.t("Pinned word ") + modelData
                            onClicked: win.recall(modelData)
                        }
                    }
                }
            }
        }
    }
}
