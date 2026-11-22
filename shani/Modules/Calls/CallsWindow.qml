// Calls: the dial pad and the call history, for every line at once — the
// landline, the computer's own mobile modem, and the mobile phone when its
// link can carry a call. One list, newest first, with the name from the
// address book where there is one.
//
// bridge/link.py does the talking (shani_link.lines for the landline and the
// modem, shani_link.phone for a phone over KDE Connect / GSConnect / plain
// Bluetooth); the window is only a view.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Calls"
    visible: Ui.calls
    onGone: Ui.calls = false
    implicitWidth: Theme.px(760)
    implicitHeight: Theme.px(620)

    // the line a new call goes out on: the first one shani-link has, or the
    // phone's when there is no landline or modem
    property string line: Link.lines.length ? Link.lines[0] : ""
    property string dialed: ""              // the number being called

    onVisibleChanged: if (visible) { Link.refresh(); if (Ui.callsNumber !== "") { number.text = Ui.callsNumber; Ui.callsNumber = ""; } }

    // ---- the dial pad -------------------------------------------------------
    // The pad is the same shape a car's is: 3 columns of digits, the number
    // above it, and Call as the one thing that leaves the window.
    ColumnLayout {
        anchors { top: parent.top; left: parent.left; margins: Theme.px(16) }
        width: Theme.px(300)
        spacing: Theme.px(10)

        Text {
            text: Tr.t("Calls")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.px(16) * Theme.fontScale
            font.weight: Font.DemiBold
        }
        Text {
            text: Tr.t("The landline, the modem and the phone — one history, whichever line it went out on.")
            color: Theme.dim
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        TextField {
            id: number
            Layout.fillWidth: true
            placeholder: Tr.t("A number")
            onAccepted: win.call()
            // Enter is Call; typing must not dial on its own
            inputMethodHints: Qt.ImhDialableCharactersOnly
        }

        // the line to call on, when there is more than one
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: Link.lines
                Choice {
                    required property string modelData
                    text: modelData
                    selected: win.line === modelData
                    onClicked: win.line = modelData
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: Theme.px(4)
            columnSpacing: Theme.px(4)
            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
                Button {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(44)
                    text: modelData
                    onClicked: number.insert(number.cursorPosition, modelData)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Button {
                Layout.fillWidth: true
                text: Tr.t("Call")
                kind: "primary"
                enabled: number.text.trim() !== ""
                onClicked: win.call()
            }
            Button {
                text: Tr.t("Delete")
                flat: true
                enabled: number.text.length > 0
                onClicked: number.remove(number.text.length - 1, 1)
            }
        }

        Text {
            visible: Link.note !== ""
            text: Link.note
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }

        Item { Layout.fillHeight: true }
    }

    function call() {
        const n = number.text.trim();
        if (n === "") return;
        win.dialed = n;
        Link.dial(n);
        number.text = "";
    }

    // ---- the history --------------------------------------------------------
    ListView {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; margins: Theme.px(16) }
        width: win.width - Theme.px(350)
        clip: true
        spacing: Theme.px(2)
        model: Link.calls
        delegate: ListRow {
            required property var modelData
            width: ListView.view.width
            icon: modelData.missed ? "call-missed" : (modelData.direction === "in" ? "call-start" : "call-end")
            title: modelData.name || modelData.number || Tr.t("Unknown")
            subtitle: [modelData.line, Link.when(modelData.when),
                       modelData.seconds > 0 ? Link.clock(modelData.seconds) : ""].filter(x => x).join("  ·  ")
            selected: false
            onClicked: { number.text = modelData.number; }
            extra: RowLayout {
                Button { text: Tr.t("Call"); flat: true; onClicked: { win.line = modelData.line || win.line; number.text = modelData.number; win.call() } }
            }
        }
        // nothing to show is not an error
        Text {
            anchors.centerIn: parent
            visible: Link.calls.length === 0
            text: Tr.t("No calls yet")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
        }
    }
}