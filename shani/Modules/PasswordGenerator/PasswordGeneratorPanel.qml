// Passwords: a strong password made on the spot, and the GPG keys on this
// computer. A password comes from Python's `secrets` (the system's own
// randomness) - never Math.random, which is not meant for secrets. Its length
// and kinds of character are picks. Saved logins are the browser's and the
// keyring's: "Passwords and Keys" (Seahorse) opens them, where it is installed.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services as Services

AppWindow {
    id: win
    appName: "Password Generator"
    visible: Ui.passwordGenerator
    onGone: Ui.passwordGenerator = false
    margins: 0
    implicitWidth: Theme.px(560)
    implicitHeight: Theme.px(560)

    // [{ name, email, id, expires }]
    property var keys: []
    property bool keysRead: false
    property string generated: ""
    property bool generatedHidden: false
    property bool generateFailed: false
    property bool wordsFallback: false
    property int length: 20
    property bool symbols: true
    property bool digits: true
    property bool words: false        // four common words, as a passphrase
    property string copied: ""

    // ---- a password, from the system's randomness ----
    function generate() {
        win.generateFailed = false;
        win.wordsFallback = false;
        gen.command = ["python3", "-c", `import secrets, string, sys
n, sym, dig, words = int(sys.argv[1]), sys.argv[2] == "1", sys.argv[3] == "1", sys.argv[4] == "1"
fallback = False
if words:
    try:
        pool = [w.strip() for w in open("/usr/share/dict/words") if w.strip().isalpha() and w.strip().islower() and 4 <= len(w.strip()) <= 8]
    except OSError:
        pool = []
    if len(pool) > 2000:
        print("-".join(secrets.choice(pool) for _ in range(max(4, n // 5))))
        sys.exit(0)
    fallback = True
alphabet = string.ascii_letters + (string.digits if dig else "") + ("!@#$%^&*()-_=+[]{};:,.?" if sym else "")
while True:
    pw = "".join(secrets.choice(alphabet) for _ in range(n))
    # one of each kind asked for, so no site refuses it
    if (not dig or any(c.isdigit() for c in pw)) and (not sym or any(not c.isalnum() for c in pw)) and any(c.islower() for c in pw) and any(c.isupper() for c in pw):
        print(("FALLBACK:" if fallback else "") + pw)
        break`, String(win.length), win.symbols ? "1" : "0", win.digits ? "1" : "0", win.words ? "1" : "0"];
        gen.running = true;
    }
    Process {
        id: gen
        stdout: StdioCollector { onStreamFinished: {
            const out = text.trim();
            if (out.startsWith("FALLBACK:")) {
                win.wordsFallback = true;
                win.generated = out.slice("FALLBACK:".length);
            } else {
                win.wordsFallback = false;
                win.generated = out;
            }
            win.generatedHidden = false;
            win.generateFailed = win.generated === "";
            if (!win.generateFailed)
                hideTimer.restart();
        } }
        onExited: code => {
            if (code !== 0) {
                win.generateFailed = true;
                win.generated = "";
            }
        }
    }
    // like the Passwords window: a generated secret is not left on screen
    Timer { id: hideTimer; interval: 30000; onTriggered: win.generatedHidden = true }
    function copy(text, what) {
        Quickshell.clipboardText = text;
        win.copied = what;
        hideTimer.restart();
        copiedTimer.restart();
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: win.copied = "" }

    // ---- the GPG keys: pub, uid and fpr records of --with-colons, made into rows ----
    function refreshKeys() { keyProc.running = true; }
    Process {
        id: keyProc
        command: ["gpg", "--list-keys", "--with-colons", "--fixed-list-mode"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let cur = null;
                for (const line of text.split("\n")) {
                    const f = line.split(":");
                    if (f[0] === "pub") {
                        cur = { id: f[4].slice(-8), expires: f[6] ? Qt.formatDate(new Date(parseInt(f[6]) * 1000), "d MMM yyyy") : "", name: "", email: "" };
                        out.push(cur);
                    } else if (f[0] === "uid" && cur && cur.name === "") {
                        const m = /^(.*?)\s*<([^>]*)>/.exec(f[9].replace(/\\x3a/g, ":"));
                        cur.name = m ? m[1] : f[9];
                        cur.email = m ? m[2] : "";
                    }
                }
                win.keys = out;
                win.keysRead = true;
            }
        }
        onExited: win.keysRead = true
    }
    Component.onCompleted: { refreshKeys(); generate(); }
    onLengthChanged: generate()
    onSymbolsChanged: generate()
    onDigitsChanged: generate()
    onWordsChanged: generate()

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.passwordGenerator = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(16)
            spacing: Theme.px(10)

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
                        text: win.copied === "password" ? Tr.t("Copied")
                            : win.generateFailed ? Tr.t("Could not generate a password")
                            : (win.generatedHidden ? "••••••••" : win.generated)
                        color: win.generateFailed ? Theme.dim : Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.mono
                        font.pixelSize: Theme.px(17) * Theme.fontScale
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Tr.t("New password")
                    }
                    IconButton {
                        visible: win.generated !== "" && !win.generateFailed
                        icon: win.generatedHidden ? "view-visible" : "view-hidden"
                        tip: win.generatedHidden ? Tr.t("Reveal password") : Tr.t("Hide password")
                        onClicked: { win.generatedHidden = !win.generatedHidden; if (!win.generatedHidden) hideTimer.restart(); }
                    }
                    IconButton {
                        icon: "view-refresh"
                        tip: Tr.t("Another one")
                        onClicked: win.generate()
                    }
                    Button {
                        kind: "primary"
                        text: Tr.t("Copy")
                        enabled: win.generated !== "" && !win.generateFailed
                        onClicked: win.copy(win.generated, "password")
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
                        selected: win.length === modelData && !win.words
                        onClicked: { win.words = false; win.length = modelData; }
                    }
                }
                Choice {
                    text: Tr.t("Words")
                    selected: win.words
                    onClicked: win.words = !win.words
                }
            }
            Text {
                Layout.fillWidth: true
                visible: win.wordsFallback
                text: Tr.t("Word list unavailable; using a character password")
                color: Theme.dim
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            SwitchRow {
                Layout.fillWidth: true
                visible: !win.words
                text: Tr.t("Digits")
                checked: win.digits
                onToggled: on => win.digits = on
            }
            SwitchRow {
                Layout.fillWidth: true
                visible: !win.words
                text: Tr.t("Symbols")
                hint: Tr.t("a few sites refuse them")
                checked: win.symbols
                onToggled: on => win.symbols = on
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.px(6)
                SectionTitle { Layout.fillWidth: true; text: Tr.t("GPG keys") }
                IconButton {
                    size: Theme.px(28)
                    icon: "view-refresh"
                    tip: Tr.t("Read again")
                    onClicked: win.refreshKeys()
                }
            }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: keyList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: win.keys
                delegate: ListRow {
                    required property var modelData
                    width: keyList.width
                    icon: "dialog-password"
                    title: modelData.name || modelData.email || modelData.id
                    subtitle: [modelData.email, modelData.id, modelData.expires ? Tr.t("until %1").arg(modelData.expires) : ""].filter(x => x).join("  ·  ")
                    trailing: win.copied === modelData.id ? Tr.t("Copied") : Tr.t("Copy ID")
                    onClicked: win.copy(modelData.id, modelData.id)
                }
                EmptyState {
                    visible: win.keysRead && keyList.count === 0
                    anchors.centerIn: parent
                    width: keyList.width - Theme.px(32)
                    icon: "dialog-password"
                    title: Tr.t("No GPG keys on this computer")
                }
            }
            Button {
                // Passwords and Keys by its desktop entry: in the niri image it is
                // a Flatpak, so there is no `seahorse` to run
                readonly property var entry: DesktopEntries.byId("org.gnome.seahorse.Application") || DesktopEntries.byId("seahorse")
                Layout.fillWidth: true
                visible: entry !== null
                text: Tr.t("Saved logins and keyrings…")
                onClicked: { Services.Launch.app(entry.id); Ui.passwordGenerator = false; }
            }
        }
    }
}
