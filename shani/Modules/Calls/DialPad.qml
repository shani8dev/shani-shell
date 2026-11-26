// The keypad, drawn as keys: three columns, digits with their letters, and a
// long press on 0 for "+". Clicking a key only hands a digit to the caller; it
// never dials by itself.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Modules.Calls

Item {
    id: root
    property bool compactKeys: false
    // Loader hands these to the pad; the pad does not know who owns the field.
    property var digitHandler: function (digit) {}
    property var longHandler: function () {}

    readonly property int keySize: root.compactKeys ? Theme.px(44) : Theme.px(56)
    readonly property int gap: Theme.px(6)
    implicitWidth: root.keySize * 3 + root.gap * 2
    implicitHeight: root.keySize * 4 + root.gap * 3

    GridLayout {
        anchors.centerIn: parent
        columns: 3
        rowSpacing: root.gap
        columnSpacing: root.gap
        Repeater {
            model: [
                { d: "1", l: "" }, { d: "2", l: "ABC" }, { d: "3", l: "DEF" },
                { d: "4", l: "GHI" }, { d: "5", l: "JKL" }, { d: "6", l: "MNO" },
                { d: "7", l: "PQRS" }, { d: "8", l: "TUV" }, { d: "9", l: "WXYZ" },
                { d: "*", l: "" }, { d: "0", l: "+" }, { d: "#", l: "" }
            ]
            PadKey {
                required property var modelData
                digit: modelData.d
                letters: modelData.l
                keySize: root.keySize
                digitHandler: root.digitHandler
                longHandler: root.longHandler
                Layout.preferredWidth: root.keySize
                Layout.preferredHeight: root.keySize
            }
        }
    }
}
