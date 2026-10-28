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
    BackgroundEffect.blurRegion: Settings.data.blur ? kbRegion : null
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

    function tap(k) {
        if (k === "⌫")
            Osk.press("BackSpace");
        else if (k === "⇧")
            Osk.shift = !Osk.shift;
        else
            Osk.press(k);
    }

    Glass {
        id: board
        strong: true
        anchors.fill: parent
        anchors.margins: 8
        anchors.bottomMargin: 6
        radius: Theme.radiusLarge

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Repeater {
                model: win.rows
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
                Key { Layout.preferredWidth: 130; Layout.fillHeight: true; label: Osk.page === "symbols" ? "abc" : (Osk.lang === "mr" ? "?१२३" : "?123"); onTapped: Osk.page = Osk.page === "symbols" ? "letters" : "symbols" }
                Key { Layout.preferredWidth: 90; Layout.fillHeight: true; label: "⇧"; visible: Osk.isXkb; accent: Osk.shift; onTapped: Osk.shift = !Osk.shift }
                Key { Layout.preferredWidth: 130; Layout.fillHeight: true; label: "⇄ " + win.nextSample; visible: Osk.languages.length > 1; onTapped: Osk.nextLanguage() }
                Key { Layout.fillWidth: true; Layout.fillHeight: true; label: win.layoutName; dim: true; onTapped: Osk.press("space") }
                Key { Layout.preferredWidth: 130; Layout.fillHeight: true; label: "⏎"; accent: true; onTapped: Osk.press("Return") }
                Key { Layout.preferredWidth: 90; Layout.fillHeight: true; label: "✕"; onTapped: Osk.toggle() }
            }
        }
    }

    component Key: Rectangle {
        id: key
        property string label
        property bool accent: false
        property bool dim: false
        signal tapped()
        radius: 10
        color: key.accent ? Theme.accent : (area.pressed ? Theme.pressed : Theme.hover)
        Text {
            anchors.centerIn: parent
            text: key.label
            color: key.accent ? Theme.accentInk : (key.dim ? Theme.dim : Theme.text)
            font.family: Theme.font
            font.pixelSize: key.label.length > 3 ? 13 : 20
        }
        MouseArea {
            id: area
            anchors.fill: parent
            onPressed: key.tapped()
        }
    }
}
