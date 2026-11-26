// Passwords and Keys > Generator: a strong password made on the spot - its
// length and kinds of character are picks, or four words as a passphrase.
// This was the Password Generator app; its GPG list was a read-only copy of
// the GPG keys tab here, so only the generator moved in.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: root
    spacing: Theme.px(10)

    property string generated: ""
    property bool generatedHidden: false
    property bool generateFailed: false
    property bool wordsFallback: false
    property int length: 20
    property bool symbols: true
    property bool digits: true
    property bool words: false        // four common words, as a passphrase
    property string copied: ""

    function generate() {
        root.generateFailed = false;
        root.wordsFallback = false;
        maker.command = PasswordGen.command(root.length, root.symbols, root.digits, root.words);
        maker.running = true;
    }
    Process {
        id: maker
        stdout: StdioCollector { onStreamFinished: {
            const out = text.trim();
            root.wordsFallback = out.startsWith("FALLBACK:");
            root.generated = root.wordsFallback ? out.slice("FALLBACK:".length) : out;
            root.generatedHidden = false;
            root.generateFailed = root.generated === "";
            if (!root.generateFailed)
                hideTimer.restart();
        } }
        onExited: code => { if (code !== 0) { root.generateFailed = true; root.generated = ""; } }
    }
    // a generated secret is not left on screen
    Timer { id: hideTimer; interval: 30000; onTriggered: root.generatedHidden = true }
    function copy() {
        Quickshell.clipboardText = root.generated;
        root.copied = "password";
        hideTimer.restart();
        copiedTimer.restart();
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copied = "" }

    // a fresh one each time the tab is shown and whenever a pick changes
    onVisibleChanged: if (visible && root.generated === "") generate()
    onLengthChanged: generate()
    onSymbolsChanged: generate()
    onDigitsChanged: generate()
    onWordsChanged: generate()

    SectionTitle { Layout.fillWidth: true; text: Tr.t("A new password") }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.px(64)
        radius: Theme.radiusSmall
        color: Theme.surface1
        border.width: 1
        border.color: Theme.stroke
        RowLayout {
            anchors { fill: parent; leftMargin: Theme.px(14); rightMargin: Theme.px(8) }
            spacing: Theme.px(8)
            Text {
                Layout.fillWidth: true
                text: root.copied === "password" ? Tr.t("Copied")
                    : root.generateFailed ? Tr.t("Could not generate a password")
                    : (root.generatedHidden ? "••••••••" : root.generated)
                color: root.generateFailed ? Theme.dim : Theme.text
                elide: Text.ElideRight
                font.family: Theme.mono
                font.pixelSize: Theme.type("subtitle")
                Accessible.role: Accessible.StaticText
                Accessible.name: Tr.t("New password")
            }
            IconButton {
                visible: root.generated !== "" && !root.generateFailed
                icon: root.generatedHidden ? "view-visible" : "view-hidden"
                tip: root.generatedHidden ? Tr.t("Reveal password") : Tr.t("Hide password")
                onClicked: { root.generatedHidden = !root.generatedHidden; if (!root.generatedHidden) hideTimer.restart(); }
            }
            IconButton { icon: "view-refresh"; tip: Tr.t("Another one"); onClicked: root.generate() }
            Button {
                kind: "primary"
                text: Tr.t("Copy")
                enabled: root.generated !== "" && !root.generateFailed
                onClicked: root.copy()
            }
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Length") }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: [12, 16, 20, 24, 32, 48]
            Choice {
                required property int modelData
                text: String(modelData)
                selected: root.length === modelData && !root.words
                onClicked: { root.words = false; root.length = modelData; }
            }
        }
        Choice { text: Tr.t("Words"); selected: root.words; onClicked: root.words = !root.words }
    }
    Text {
        Layout.fillWidth: true
        visible: root.wordsFallback
        text: Tr.t("Word list unavailable; using a character password")
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.type("body")
    }
    SwitchRow {
        Layout.fillWidth: true
        visible: !root.words
        text: Tr.t("Digits")
        checked: root.digits
        onToggled: on => root.digits = on
    }
    SwitchRow {
        Layout.fillWidth: true
        visible: !root.words
        text: Tr.t("Symbols")
        hint: Tr.t("a few sites refuse them")
        checked: root.symbols
        onToggled: on => root.symbols = on
    }
    Item { Layout.fillHeight: true }
}
