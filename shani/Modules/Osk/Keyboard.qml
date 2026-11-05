// The screen keyboard. It never takes keyboard focus (taps on a layer surface
// with focus None leave the app's text field focused), reserves the bottom of
// the screen like a phone keyboard, and types through Services/Osk.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Osk.shown && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { bottom: true; left: true; right: true }
    implicitHeight: 300
    exclusiveZone: 300
    color: "transparent"
    WlrLayershell.namespace: "shani-osk"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted ? kbRegion : null
    Region { id: kbRegion; item: board; radius: Theme.radiusLarge }

    readonly property var layouts: ({
        "en": {
            name: "English",
            letters: [
                "q w e r t y u i o p".split(" "),
                "a s d f g h j k l".split(" "),
                ["⇧"].concat("z x c v b n m".split(" ")).concat(["⌫"])
            ],
            symbols: [
                "1 2 3 4 5 6 7 8 9 0".split(" "),
                "@ # ₹ _ & - + ( ) /".split(" "),
                "* \" ' : ; ! ? , .".split(" ").concat(["⌫"])
            ]
        },
        "mr": {
            name: "मराठी",
            letters: [
                "अ आ इ ई उ ऊ ए ऐ ओ औ".split(" "),
                "क ख ग घ ङ च छ ज झ ञ".split(" "),
                "ट ठ ड ढ ण त थ द ध न".split(" "),
                "प फ ब भ म य र ल व ळ".split(" "),
                "श ष स ह क्ष ज्ञ ् ं ः".split(" ").concat(["⌫"])
            ],
            symbols: [
                "० १ २ ३ ४ ५ ६ ७ ८ ९".split(" "),
                "ऋ ॲ ऑ ँ ़ ऱ । ॥ ॐ ₹".split(" "),
                ", . ? ! - ( ) : '".split(" ").concat(["⌫"])
            ]
        }
    })
    // Every layout as rows of { n: base, s: shifted } keys. Hand-made ones are
    // above; anything else is generated from xkb (Services/Osk.xkb).
    function keysOf(row, upper) {
        return row.map(k => ({ n: k, s: upper && k.length === 1 ? k.toUpperCase() : k }));
    }
    readonly property var hand: layouts[Osk.lang] || null
    readonly property string layoutName: hand ? hand.name : (Osk.current ? Osk.current.name : Osk.lang)
    readonly property var rows: {
        if (Osk.page === "symbols" || (!hand && !Osk.current))
            return (hand || layouts["en"]).symbols.map(r => keysOf(r, false));
        if (hand)
            return hand.letters.map(r => keysOf(r, Osk.lang === "en"));
        // xkb: the letter rows (the number row lives on the symbols page)
        const r = Osk.current.rows.slice(1).map(row => row.slice());
        if (r.length)
            r[r.length - 1].push({ n: "⌫", s: "⌫" });
        return r;
    }
    // the next language, shown on the switch key by a few of its own letters
    readonly property string nextSample: {
        const ls = Osk.languages;
        const next = ls[(Osk.langIndex + 1) % ls.length];
        if (next === "en") return "abc";
        if (next === "mr") return "अआइ";
        const m = Osk.xkb[next];
        return m && m.rows.length > 1 ? m.rows[1].slice(0, 3).map(k => k.n).join("") : next;
    }

    // the language list, over the keys: each language, and adding one in Settings
    property bool langMenu: false
    function langName(id) { return (layouts[id] && layouts[id].name) || (Osk.xkb[id] && Osk.xkb[id].name) || id; }

    function tap(k) {
        if (k === "⌫")
            Osk.press("BackSpace");
        else if (k === "⇧")
            Osk.shift = !Osk.shift;
        else
            Osk.press(k);
    }

    onVisibleChanged: if (visible) boardIn.restart()
    NumberAnimation { id: boardIn; target: boardRise; property: "y"; from: 60; to: 0; duration: Theme.anim * 1.5; easing.type: Easing.OutCubic }

    Glass {
        id: board
        transform: Translate { id: boardRise }
        strong: true
        anchors.fill: parent
        anchors.margins: 8
        anchors.bottomMargin: 6
        radius: Theme.radiusLarge

        Glass {
            visible: win.langMenu
            z: 5
            strong: true
            radius: 14
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 70
            width: 300
            height: langCol.implicitHeight + 16
            Column {
                id: langCol
                x: 8; y: 8
                width: parent.width - 16
                Repeater {
                    model: Osk.languages
                    ListRow {
                        required property string modelData
                        required property int index
                        width: langCol.width
                        icon: "preferences-desktop-locale"
                        title: win.langName(modelData)
                        selected: index === Osk.langIndex % Osk.languages.length
                        onClicked: { Osk.langIndex = index; win.langMenu = false; }
                    }
                }
                ListRow {
                    width: langCol.width
                    icon: "list-add"
                    title: Tr.t("Add a language…")
                    onClicked: { win.langMenu = false; Osk.toggle(); Ui.openSettings("input"); }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // the handwriting pad, in place of the letters; editing keys beside it
            RowLayout {
                visible: Osk.page === "write"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 3
                spacing: 6
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: Theme.alpha(Theme.text, 0.04)
                    border.color: Theme.stroke
                    WritePad { anchors.fill: parent; visible: Osk.page === "write" }
                }
                GridLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 200
                    columns: 2
                    rowSpacing: 6
                    columnSpacing: 6
                    Repeater {
                        model: [{ l: "⌫", k: "BackSpace" }, { l: "⌦", k: "Delete" }, { l: "⇥", k: "Tab" }, { l: "Esc", k: "Escape" },
                                { l: "←", k: "Left" }, { l: "→", k: "Right" }, { l: "↑", k: "Up" }, { l: "↓", k: "Down" }]
                        Key { required property var modelData; Layout.fillWidth: true; Layout.fillHeight: true; label: modelData.l; onTapped: Osk.press(modelData.k) }
                    }
                }
            }
            Repeater {
                model: Osk.page === "write" ? [] : win.rows
                RowLayout {
                    id: keyRow
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6
                    Repeater {
                        model: keyRow.modelData
                        Key {
                            required property var modelData
                            readonly property string ch: Osk.shift ? modelData.s : modelData.n
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: ch === "⇧" || ch === "⌫" ? 150 : 100
                            label: ch
                            accent: (ch === "⇧" && Osk.shift) || ch === "्"
                            onTapped: win.tap(ch)
                        }
                    }
                }
            }

            // the bottom row: page, language, space, enter, hide
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                Key { Layout.preferredWidth: 130; Layout.fillHeight: true; label: Osk.page !== "letters" ? "abc" : (Osk.lang === "mr" ? "?१२३" : "?123"); onTapped: Osk.page = Osk.page !== "letters" ? "letters" : "symbols" }
                // write by hand; Ctrl and Alt, sticky (one tap: the next key; two: held)
                Key { Layout.preferredWidth: 80; Layout.fillHeight: true; label: "✍"; accent: Osk.page === "write"; onTapped: Osk.page = Osk.page === "write" ? "letters" : "write"; Accessible.name: Tr.t("Write by hand") }
                Key { Layout.preferredWidth: 80; Layout.fillHeight: true; label: Osk.ctrl === 2 ? "Ctrl ●" : "Ctrl"; accent: Osk.ctrl > 0; onTapped: Osk.tapMod("ctrl") }
                Key { Layout.preferredWidth: 80; Layout.fillHeight: true; label: Osk.alt === 2 ? "Alt ●" : "Alt"; accent: Osk.alt > 0; onTapped: Osk.tapMod("alt") }
                Key { Layout.preferredWidth: 90; Layout.fillHeight: true; label: "⇧"; visible: Osk.isXkb; accent: Osk.shift; onTapped: Osk.shift = !Osk.shift }
                // the globe (Gboard's): a tap - the next language, or the list when there is
                // only one (so adding one is never hidden); held - the list
                Key {
                    id: globe
                    Layout.preferredWidth: 110
                    Layout.fillHeight: true
                    label: Osk.languages.length > 1 ? "🌐 " + win.nextSample : "🌐"
                    Accessible.name: Tr.t("Keyboard language")
                    holdable: true
                    onTapped: Osk.languages.length > 1 ? Osk.nextLanguage() : (win.langMenu = !win.langMenu)
                    onHeld: win.langMenu = true
                }
                // voice typing: tap, speak, tap again — the words land where the keys would
                Key {
                    Layout.preferredWidth: 90
                    Layout.fillHeight: true
                    label: Dictation.phase === "transcribing" ? "…" : ""
                    icon: Dictation.phase === "transcribing" ? "" : "audio-input-microphone"
                    accent: Dictation.phase === "recording"
                    danger: Dictation.phase === "recording"
                    onTapped: Dictation.toggle()
                }
                Key { Layout.fillWidth: true; Layout.fillHeight: true; label: win.layoutName; dim: true; onTapped: Osk.press("space") }
                Key { Layout.preferredWidth: 130; Layout.fillHeight: true; label: "⏎"; accent: true; onTapped: Osk.press("Return") }
                // hide it to see the whole screen; the floating button (OskButton) or the bar brings it back
                Key { Layout.preferredWidth: 90; Layout.fillHeight: true; label: "⌄"; Accessible.name: Tr.t("Hide keyboard"); onTapped: Osk.toggle() }
            }
        }
    }

    component Key: Rectangle {
        id: key
        property string label
        property bool accent: false
        property bool danger: false
        property string icon: ""
        property bool dim: false
        signal tapped()
        signal held()
        property bool holdable: false      // has something to show when held: waits for the release

        Accessible.role: Accessible.Button
        Accessible.name: key.icon !== "" ? "microphone" : key.label
        Accessible.onPressAction: key.tapped()
        radius: 10
        color: key.danger ? Theme.red : key.accent ? Theme.accent : (area.pressed ? Theme.pressed : Theme.hover)
        Icon {
            visible: key.icon !== ""
            anchors.centerIn: parent
            name: key.icon
            size: 22
            color: key.accent || key.danger ? Theme.accentInk : Theme.text
        }
        Text {
            anchors.centerIn: parent
            text: key.label
            color: key.accent ? Theme.accentInk : (key.dim ? Theme.dim : Theme.text)
            font.family: Theme.font
            font.pixelSize: (key.label.length > 3 ? 13 : 20) * Theme.fontScale
        }
        MouseArea {
            id: area
            anchors.fill: parent
            // a key types on press (fast typing); one that can be held waits for the release
            onPressed: if (!key.holdable) key.tapped()
            onClicked: if (key.holdable) key.tapped()
            pressAndHoldInterval: 450
            onPressAndHold: if (key.holdable) key.held()
        }
    }
}
