// Calls: the dial pad and the call history, for every line at once — the
// landline, the computer's own mobile modem, and the mobile phone when its
// link can carry a call. One list, newest first, with the name from the
// address book where there is one.
//
// bridge/link.py does the talking (phone.lines for the landline and the
// modem, phone.phone for a phone over KDE Connect / GSConnect / plain
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

    // the line a new call goes out on: the first one shani-shell has, or the
    // phone's when there is no landline or modem
    property string line: Link.lines.length ? Link.lines[0] : ""
    property string dialed: ""              // the number being called
    property string callSearch: ""          // recents filter, lowercased
    property bool missedOnly: false

    onVisibleChanged: if (visible) { Link.refresh(); if (Ui.callsNumber !== "") { number.text = Ui.callsNumber; Ui.callsNumber = ""; } }

    // ---- the dial pad -------------------------------------------------------
    // The pad is the same shape a car's is: 3 columns of digits, the number
    // above it, and Call as the one thing that leaves the window.
    ColumnLayout {
        anchors { top: parent.top; left: parent.left; margins: Theme.px(16) }
        width: Theme.px(300)
        spacing: Theme.px(10)

        // ---- the call in progress -------------------------------------------------
        // shani-shell rings the call; this is the shell's own live view of it, with
        // Mute/Speaker on the bridge's callctl verb and Hang up on the call itself.
        Glass {
            visible: Modem.call !== null
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(104)
            solid: true
            ColumnLayout {
                anchors { fill: parent; margins: Theme.px(10) }
                spacing: Theme.px(4)
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: Modem.call ? (Modem.call.name || Modem.call.number || Tr.t("Unknown")) : ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        text: Modem.callTime
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Button {
                        Layout.fillWidth: true
                        text: Tr.t("Mute")
                        checked: Modem.muted
                        onClicked: Modem.setMute(!Modem.muted)
                    }
                    Button {
                        Layout.fillWidth: true
                        text: Tr.t("Speaker")
                        checked: Modem.speaker
                        onClicked: Modem.setSpeaker(!Modem.speaker)
                    }
                    Button {
                        Layout.fillWidth: true
                        text: Tr.t("Hang up")
                        kind: "danger"
                        onClicked: Modem.hangup()
                    }
                }
            }
        }

        // a second call arrived: keep the first one up and offer the usual three
        Glass {
            visible: Modem.waitingCall !== null
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(80)
            solid: true
            ColumnLayout {
                anchors { fill: parent; margins: Theme.px(8) }
                spacing: Theme.px(4)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Call waiting") + ": " + (Modem.waitingCall ? (Modem.waitingCall.name || Modem.waitingCall.number || Tr.t("Unknown")) : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Button {
                        Layout.fillWidth: true
                        text: Tr.t("Answer")
                        kind: "primary"
                        enabled: Modem.waitingCall !== null
                        onClicked: Modem.answerCall(Modem.waitingCall.path)
                    }
                    Button {
                        Layout.fillWidth: true
                        text: Tr.t("Hold")
                        onClicked: Modem.callctl("hold")
                    }
                    Button {
                        Layout.fillWidth: true
                        text: Tr.t("Swap")
                        onClicked: Modem.callctl("swap")
                    }
                }
            }
        }

        // the title is the window's own (AppWindow's header), not repeated here
        Text {
            // a wrapping Text in a layout needs the layout's width, or it is
            // laid out at its full one-line length and runs under the history
            Layout.fillWidth: true
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
                    // keys look like keys: an outline at rest, not bare digits
                    kind: "outline"
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
                onClicked: win.deleteDigit()
            }
        }

        Text {
            Layout.fillWidth: true
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

    // backspace at the caret (or the whole selection), not always the last digit
    function deleteDigit() {
        if (number.selectionStart !== number.selectionEnd) {
            number.remove(number.selectionStart, number.selectionEnd - number.selectionStart);
            return;
        }
        if (number.cursorPosition > 0) number.remove(number.cursorPosition - 1, 1);
    }

    // ---- the history --------------------------------------------------------
    ColumnLayout {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; margins: Theme.px(16) }
        width: win.width - Theme.px(350)
        spacing: Theme.px(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: recentsSearch
                Layout.fillWidth: true
                placeholder: Tr.t("Search calls")
                onTextChanged: win.callSearch = text.trim().toLowerCase()
            }
            Choice {
                text: Tr.t("Missed only")
                selected: win.missedOnly
                onClicked: win.missedOnly = !win.missedOnly
            }
        }

        ListView {
            id: recents
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.px(2)
            // the filter is over the existing Link.calls model, not a new store
            model: Link.calls.filter(c => (!win.missedOnly || c.missed)
                   && (win.callSearch === "" || (c.name || c.number || "").toLowerCase().indexOf(win.callSearch) >= 0))
            delegate: ListRow {
                required property var modelData
                width: ListView.view.width
                icon: modelData.missed ? "call-missed" : (modelData.direction === "in" ? "call-start" : "call-end")
                title: modelData.name || modelData.number || Tr.t("Unknown")
                subtitle: [modelData.line, Link.when(modelData.when),
                           modelData.seconds > 0 ? Link.clock(modelData.seconds) : ""].filter(x => x).join("  ·  ")
                selected: false
                // a tap fills the pad: put the caret at the end and focus it so
                // Enter calls and typing continues without a Tab
                onClicked: { number.text = modelData.number; number.cursorPosition = number.text.length; number.forceActiveFocus(); }
                extra: RowLayout {
                    Button { text: Tr.t("Call"); flat: true; onClicked: { win.line = modelData.line || win.line; number.text = modelData.number; win.call() } }
                }
            }
            // nothing to show is not an error
            Text {
                anchors.centerIn: parent
                visible: recents.count === 0
                text: win.callSearch !== "" || win.missedOnly ? Tr.t("No calls match") : Tr.t("No calls yet")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
        }
    }
}
