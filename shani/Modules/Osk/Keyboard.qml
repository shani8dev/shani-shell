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
    color: "transparent"
    WlrLayershell.namespace: "shani-osk"
    WlrLayershell.layer: WlrLayer.Overlay
    // remote mode takes the keys (arrows, OK, Back); otherwise never, so the
    // app's field keeps the focus and the keys type into it
    WlrLayershell.keyboardFocus: Osk.remote ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // compact keeps every key but makes each row shorter; the fixed size is
    // the original full keyboard. Remote keeps its own taller draft line.
    implicitHeight: {
        const full = Osk.remote ? 360 : (Osk.compact ? 232 : 300);
        return Math.min(full, screen ? Math.floor(screen.height * 0.6) : full);
    }
    exclusiveZone: implicitHeight
    Binding { target: Osk; property: "height"; value: win.visible ? win.height : 0 }
    Binding { target: Osk; property: "output"; value: win.visible && win.screen ? win.screen.name : "" }
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
    // the keyboard's own size / opacity / suggestions controls (Settings has no OSK page)
    property bool oskMenu: false
    function langName(id) { return (layouts[id] && layouts[id].name) || (Osk.xkb[id] && Osk.xkb[id].name) || id; }

    function tap(k) {
        if (k === "⌫")
            Osk.press("BackSpace");
        else if (k === "⇧")
            Osk.shift = !Osk.shift;
        else
            Osk.press(k);
    }

    // ---- a controller on the keys (Services/Osk.pad): a highlighted key moved by
    // where the keys are on screen, so every layout - hand-made, xkb, the
    // handwriting page's side keys, the wide bottom row - works the same
    property Item cursor: null
    property point cursorAt: Qt.point(0, 0)  // where it was: a new page keeps it near
    onCursorChanged: Osk.cursorLabel = cursor ? cursor.label : ""
    function keyItems(item, out) {
        for (const c of item.children) {
            if (c.isOskKey === true) {
                if (c.visible && c.width > 0)
                    out.push(c);
            } else if (c.visible !== false)
                keyItems(c, out);
        }
        return out;
    }
    function centre(k) { return k.mapToItem(board, k.width / 2, k.height / 2); }
    function nearest(keys, p) {
        let best = null, bd = Infinity;
        for (const k of keys) {
            const c = centre(k), d = Math.hypot(c.x - p.x, (c.y - p.y) * 2);
            if (d < bd) { bd = d; best = k; }
        }
        return best;
    }
    function setCursor(k) {
        cursor = k;
        if (k) cursorAt = centre(k);
    }
    function padMove(dir) {
        const keys = keyItems(board, []);
        if (!keys.length)
            return;
        if (!cursor || keys.indexOf(cursor) < 0) {      // first use, or the page changed under it
            setCursor(nearest(keys, cursorAt.x || cursorAt.y ? cursorAt : centre(keys[0])));
            return;
        }
        const here = centre(cursor);
        const rowOf = k => keys.filter(o => Math.abs(centre(o).y - centre(k).y) < k.height / 2);
        if (dir === "left" || dir === "right") {
            const row = rowOf(cursor).sort((a, b) => centre(a).x - centre(b).x);
            const i = row.indexOf(cursor) + (dir === "right" ? 1 : -1);
            setCursor(row[(i + row.length) % row.length]);
            return;
        }
        // up / down: the key nearest across in the row above or below (wrapping)
        const ys = [];
        for (const k of keys) {
            const y = centre(k).y;
            if (!ys.some(v => Math.abs(v - y) < k.height / 2))
                ys.push(y);
        }
        ys.sort((a, b) => a - b);
        const at = ys.findIndex(v => Math.abs(v - here.y) < cursor.height / 2);
        const to = ys[(at + (dir === "down" ? 1 : -1) + ys.length) % ys.length];
        const row = keys.filter(k => Math.abs(centre(k).y - to) < k.height / 2);
        setCursor(nearest(row, Qt.point(here.x, to)));
    }
    Connections {
        target: Osk
        function onPadMove(direction) { win.padMove(direction); }
        function onPadTap() {
            if (!win.cursor)
                win.padMove("none");
            else
                win.cursor.tapped();
        }
        function onShownChanged() { win.cursor = null; win.cursorAt = Qt.point(0, 0); win.langMenu = false; win.oskMenu = false; }
    }

    // The remote draft is drawn by the OSK itself, so it never inherits the
    // target field's echoMode. Mirror it: shell fields register with
    // Ui.textInput (Common/TextField.qml), whose echoMode says if it is a secret.
    // Limits: fields outside the shell never register, and the OSK's exclusive
    // keyboard focus can clear Ui.textInput right after it opens, so latch the
    // secret state on focus-in and fall back to Ui.promptKeyboard. shell.qml
    // still copies the raw draft/typed text into state dumps — that needs a
    // shell.qml change, which is out of scope here.
    property bool draftSecret: false
    readonly property bool targetIsSecret: draftSecret || Ui.promptKeyboard ||
        (Ui.textInput !== null && Ui.textInput.echoMode !== TextInput.Normal)
    readonly property string shownDraft: Osk.draft === "" ? "" :
        (targetIsSecret ? "•".repeat(Osk.draft.length) : Osk.draft)
    Connections {
        target: Ui
        function onTextInputChanged() {
            if (Ui.textInput && Ui.textInput.echoMode !== TextInput.Normal)
                win.draftSecret = true;
        }
    }
    Connections {
        target: Osk
        function onRemoteChanged() { if (!Osk.remote) win.draftSecret = false; }
    }

    onVisibleChanged: if (visible) boardIn.restart()
    // the remote's keys, in remote mode: the same moves as a controller's
    Item {
        id: remoteKeys
        focus: Osk.remote
        Keys.onPressed: e => {
            const move = { [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Left]: "left", [Qt.Key_Right]: "right" }[e.key];
            if (move) Osk.pad(move);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Select) Osk.pad("press");
            else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Back) Osk.cancelRemote();
            else if (e.key === Qt.Key_Backspace) Osk.press("BackSpace");
            else if (e.text !== "" && e.text.trim() !== "" && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier))) Osk.press(e.text);
            else return;
            e.accepted = true;
        }
    }
    Connections {
        target: Osk
        function onRemoteChanged() { if (Osk.remote) focusLater.restart(); }
    }
    // after the window is up and niri has given it the keys
    Timer { id: focusLater; interval: 120; onTriggered: if (Osk.remote) remoteKeys.forceActiveFocus() }
    NumberAnimation { id: boardIn; target: boardRise; property: "y"; from: 60; to: 0; duration: Theme.anim * 1.5; easing.type: Easing.OutCubic }

    Glass {
        id: board
        transform: Translate { id: boardRise }
        strong: true
        anchors.fill: parent
        anchors.margins: Theme.px(8)
        anchors.bottomMargin: Theme.px(6)
        radius: Theme.radiusLarge
        opacity: Osk.panelOpacity
        Behavior on opacity { NumberAnimation { duration: Theme.mot(140) } }

        Glass {
            visible: win.oskMenu
            z: 6
            strong: true
            radius: Theme.px(14)
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.px(70)
            width: Theme.px(320)
            height: menuCol.implicitHeight + 16
            Column {
                id: menuCol
                x: 8; y: 8
                width: parent.width - 16
                ListRow {
                    width: menuCol.width
                    icon: "input-keyboard"
                    title: Osk.compact ? Tr.t("Keyboard: compact") : Tr.t("Keyboard: fixed")
                    onClicked: Osk.toggleSize()
                }
                ListRow {
                    width: menuCol.width
                    icon: "preferences-desktop"
                    title: Tr.t("Keyboard opacity: %1%", Math.round(Osk.panelOpacity * 100))
                    onClicked: Osk.cycleOpacity()
                }
                ListRow {
                    width: menuCol.width
                    icon: "edit-find"
                    title: Osk.suggestions ? Tr.t("Word suggestions: on") : Tr.t("Word suggestions: off")
                    onClicked: Osk.toggleSuggestions()
                }
            }
        }

        Glass {
            visible: win.langMenu
            z: 5
            strong: true
            radius: Theme.px(14)
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.px(70)
            width: Theme.px(300)
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
            anchors.margins: Theme.px(Osk.compact ? 6 : 10)
            spacing: Theme.px(Osk.compact ? 4 : 6)

            // remote mode: what is being typed, before it goes to the app
            Rectangle {
                visible: Osk.remote
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(48)
                radius: Theme.px(10)
                color: Theme.alpha(Theme.text, 0.06)
                border.color: Theme.accent
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.px(14)
                    text: Osk.draft === "" ? Tr.t("Type with the arrows and OK · Done sends it · Back cancels") : win.shownDraft + "▏"
                    color: Osk.draft === "" ? Theme.dim : Theme.text
                    font.family: Theme.font
                    font.pixelSize: (Osk.draft === "" ? 14 : 20) * Theme.fontScale
                }
            }

            // inline word suggestions, above the keys: a small bounded English
            // list in Osk, not a dictionary service. The × hides this word only.
            Rectangle {
                id: suggestionBar
                readonly property string word: Osk.currentWord()
                readonly property var picks: Osk.suggestionsFor(word)
                visible: Osk.suggestions && Osk.lang === "en" && Osk.page === "letters" &&
                         Osk.dismissedWord !== word && picks.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Theme.px(34) : 0
                radius: Theme.px(10)
                color: Theme.alpha(Theme.text, 0.04)
                border.color: Theme.stroke
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(3)
                    spacing: Theme.px(4)
                    Repeater {
                        model: suggestionBar.picks
                        Key {
                            required property string modelData
                            Layout.preferredWidth: Theme.px(130)
                            Layout.fillHeight: true
                            label: modelData
                            accessibleName: Tr.t("Use %1", modelData)
                            onTapped: Osk.applySuggestion(modelData)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Key {
                        Layout.preferredWidth: Theme.px(34)
                        Layout.fillHeight: true
                        label: "×"
                        accessibleName: Tr.t("Dismiss suggestions")
                        onTapped: Osk.dismissSuggestions()
                    }
                }
            }

            // the handwriting pad, in place of the letters; editing keys beside it
            RowLayout {
                visible: Osk.page === "write"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Theme.px(3)
                spacing: Theme.px(6)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.px(10)
                    color: Theme.alpha(Theme.text, 0.04)
                    border.color: Theme.stroke
                    WritePad { anchors.fill: parent; visible: Osk.page === "write" }
                }
                GridLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: Theme.px(200)
                    columns: 2
                    rowSpacing: Theme.px(6)
                    columnSpacing: Theme.px(6)
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
                    spacing: Theme.px(6)
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
                spacing: Theme.px(6)
                Key { Layout.preferredWidth: Theme.px(130); Layout.fillHeight: true; label: Osk.page !== "letters" ? "abc" : (Osk.lang === "mr" ? "?१२३" : "?123"); onTapped: Osk.page = Osk.page !== "letters" ? "letters" : "symbols" }
                // write by hand; Ctrl and Alt, sticky (one tap: the next key; two: held)
                Key { Layout.preferredWidth: Theme.px(80); Layout.fillHeight: true; label: "WRITE"; accent: Osk.page === "write"; onTapped: Osk.page = Osk.page === "write" ? "letters" : "write"; accessibleName: Tr.t("Write by hand") }
                Key { Layout.preferredWidth: Theme.px(80); Layout.fillHeight: true; label: Osk.ctrl === 2 ? "Ctrl ●" : "Ctrl"; accent: Osk.ctrl > 0; onTapped: Osk.tapMod("ctrl") }
                Key { Layout.preferredWidth: Theme.px(80); Layout.fillHeight: true; label: Osk.alt === 2 ? "Alt ●" : "Alt"; accent: Osk.alt > 0; onTapped: Osk.tapMod("alt") }
                // size, opacity and suggestions, without leaving the keyboard
                Key { Layout.preferredWidth: Theme.px(70); Layout.fillHeight: true; label: "⚙"; accessibleName: Tr.t("Keyboard options"); accent: win.oskMenu; onTapped: { win.langMenu = false; win.oskMenu = !win.oskMenu; } }
                Key { Layout.preferredWidth: Theme.px(90); Layout.fillHeight: true; label: "⇧"; visible: Osk.isXkb; accent: Osk.shift; onTapped: Osk.shift = !Osk.shift }
                // the globe (Gboard's): a tap - the next language, or the list when there is
                // only one (so adding one is never hidden); held - the list
                Key {
                    id: globe
                    Layout.preferredWidth: Theme.px(110)
                    Layout.fillHeight: true
                    label: Osk.languages.length > 1 ? "LANG " + win.nextSample : "LANG"
                    accessibleName: Tr.t("Keyboard language")
                    holdable: true
                    onTapped: { win.oskMenu = false; Osk.languages.length > 1 ? Osk.nextLanguage() : (win.langMenu = !win.langMenu); }
                    onHeld: { win.oskMenu = false; win.langMenu = true; }
                }
                // voice typing: tap, speak, tap again — the words land where the keys would
                Key {
                    Layout.preferredWidth: Theme.px(90)
                    Layout.fillHeight: true
                    label: Dictation.phase === "transcribing" ? "…" : ""
                    icon: Dictation.phase === "transcribing" ? "" : "audio-input-microphone"
                    accent: Dictation.phase === "recording"
                    danger: Dictation.phase === "recording"
                    onTapped: Dictation.toggle()
                }
                Key { Layout.fillWidth: true; Layout.fillHeight: true; label: win.layoutName; dim: true; onTapped: Osk.press("space") }
                Key { Layout.preferredWidth: Theme.px(130); Layout.fillHeight: true; label: Osk.remote ? Tr.t("Done") : "⏎"; accent: true; onTapped: Osk.remote ? Osk.commit() : Osk.press("Return") }
                // hide it to see the whole screen; the floating button (OskButton) or the bar brings it back
                Key { Layout.preferredWidth: Theme.px(90); Layout.fillHeight: true; label: "⌄"; Accessible.name: Tr.t("Hide keyboard"); onTapped: Osk.remote ? Osk.cancelRemote() : Osk.toggle() }
            }
        }
    }

    component Key: Rectangle {
        id: key
        readonly property bool isOskKey: true
        property string label
        property bool accent: false
        property bool danger: false
        property string icon: ""
        property bool dim: false
        signal tapped()
        signal held()
        property bool holdable: false      // has something to show when held: waits for the release

        Accessible.role: Accessible.Button
        property string accessibleName: ""
        // instances may name themselves; the icon default must not overwrite it
        Accessible.name: key.accessibleName !== "" ? key.accessibleName : (key.icon !== "" ? Tr.t("Microphone") : key.label)
        Accessible.onPressAction: key.tapped()
        radius: Theme.px(10)
        color: key.danger ? Theme.red : key.accent ? Theme.accent : (area.pressed ? Theme.pressed : Theme.hover)
        // the controller's cursor
        border.width: Osk.padDriven && win.cursor === key ? 3 : 0
        border.color: Theme.accent
        scale: Osk.padDriven && win.cursor === key ? 1.06 : 1
        z: Osk.padDriven && win.cursor === key ? 1 : 0
        Behavior on scale { NumberAnimation { duration: Theme.anim / 2 } }
        Icon {
            visible: key.icon !== ""
            anchors.centerIn: parent
            name: key.icon
            size: Theme.px(22)
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
