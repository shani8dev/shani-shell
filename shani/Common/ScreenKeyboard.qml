// A screen keyboard for the screens before the desktop (the sign-in screen, first
// setup): drawn in their own window, typing straight into the field that has
// focus - no virtual-keyboard protocol, no shell services, which those screens
// do not have. Letters, then digits and symbols; Shift; Backspace; Enter.
// The desktop's own keyboard (Modules/Osk) types into any app instead.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property Item target: null            // a TextInput (a Field's .input)
    signal entered()
    signal hideRequested()                // the ⌄ key: the screen this sits on hides it
    property bool shift: false
    property bool symbols: false

    implicitHeight: 280
    radius: Theme.radiusLarge
    color: Theme.alpha(Theme.bg, 0.92)
    border.width: 1
    border.color: Theme.stroke

    readonly property var rows: symbols
        ? ["1 2 3 4 5 6 7 8 9 0", "@ # $ % & * - + ( )", "! \" ' : ; / ? , ."]
        : ["q w e r t y u i o p", "a s d f g h j k l", "z x c v b n m"]

    function type(ch) {
        if (!target)
            return;
        const c = !symbols && shift ? ch.toUpperCase() : ch;
        target.insert(target.cursorPosition, c);
        if (shift && !symbols)
            shift = false;                // one capital, as a phone keyboard does
    }
    function back() {
        if (target && target.cursorPosition > 0)
            target.remove(target.cursorPosition - 1, target.cursorPosition);
    }

    component Key: Rectangle {
        id: key
        property string label
        property bool accent: false
        signal tapped()
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.radiusSmall
        color: tap.pressed ? Theme.pressed : accent ? Theme.accentSoft : Theme.alpha(Theme.text, 0.08)
        Text {
            anchors.centerIn: parent
            text: key.label
            color: key.accent ? Theme.accent : Theme.text
            font.family: Theme.font
            font.pixelSize: 18 * Theme.fontScale
        }
        Accessible.role: Accessible.Button
        Accessible.name: key.label
        Accessible.onPressAction: key.tapped()
        MouseArea { id: tap; anchors.fill: parent; onClicked: key.tapped() }
        KeyFocus { onActivated: key.tapped() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6
        Repeater {
            model: root.rows
            RowLayout {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: true
                // the third row of letters sits between Shift and Backspace
                Key { visible: index === 2; label: root.symbols ? "" : "⇧"; accent: root.shift; Layout.maximumWidth: 90; onTapped: root.shift = !root.shift }
                Repeater {
                    model: modelData.split(" ")
                    Key {
                        required property string modelData
                        label: !root.symbols && root.shift ? modelData.toUpperCase() : modelData
                        onTapped: root.type(modelData)
                    }
                }
                Key { visible: index === 2; label: "⌫"; Layout.maximumWidth: 90; onTapped: root.back() }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Key { label: root.symbols ? "abc" : "?123"; Layout.maximumWidth: 110; onTapped: root.symbols = !root.symbols }
            Key { label: "space"; onTapped: root.type(" ") }
            Key { label: "⏎"; accent: true; Layout.maximumWidth: 110; onTapped: root.entered() }
            Key { label: "⌄"; Accessible.name: Tr.t("Hide keyboard"); Layout.maximumWidth: 70; onTapped: root.hideRequested() }
        }
    }
}
