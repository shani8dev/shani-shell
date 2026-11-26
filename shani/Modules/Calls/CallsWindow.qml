// Calls: the dial pad and the call history, for every line at once — the
// landline, the computer's own mobile modem, and the mobile phone when its
// link can carry a call. One list, newest first, with the name from the
// address book where there is one.
//
// bridge/link.py does the talking (phone.lines for the landline and the
// modem, phone.phone for a phone over a phone link or plain Bluetooth); the
// window is only a view. The other tabs ask PhoneTools for
// the phone's music, files and remote keys; none of them speaks to a tool.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Calls

AppWindow {
    id: win
    appName: "Calls"
    visible: Ui.calls
    onGone: Ui.calls = false
    implicitWidth: Theme.px(940)
    implicitHeight: Theme.px(700)

    readonly property var tabs: [
        ["calls", Tr.t("Calls")],
        ["music", Tr.t("Music")],
        ["files", Tr.t("Files")],
        ["remote", Tr.t("Remote")]
    ]
    property string tab: "calls"
    property bool showDtmf: false

    // the line a new call goes out on: the first one shani-shell has, or the
    // phone's when there is no landline or modem
    property string line: Link.lines.length ? Link.lines[0] : ""
    property string dialed: ""              // the number being called
    property string callSearch: ""          // recents filter, lowercased
    property bool missedOnly: false
    property var suggestions: []            // contacts matching what is typed
    property bool held: false               // the live call is on hold
    property string dtmfDigits: ""          // digits sent to the live call's keypad

    readonly property bool lineReady: Link.lines.length > 0 || Link.state === "ready"
        || Modem.canCall || Link.phone !== null
    readonly property bool inCall: Modem.call !== null

    onVisibleChanged: if (visible) { Link.refresh(); PhoneTools.refresh(); if (Ui.callsNumber !== "") { number.text = Ui.callsNumber; Ui.callsNumber = ""; } }
    Connections { target: number; function onTextChanged() { Ui.callsPad = number.text; } }

    Connections {
        target: Modem
        function onCallChanged() {
            if (Modem.call === null) { win.held = false; win.dtmfDigits = ""; win.showDtmf = false; }
        }
    }

    // ---- the address book ---------------------------------------------------
    // Already in Link.contacts; search name and digits so a pasted number with
    // spaces still finds its contact.
    function matchesFor(text) {
        const raw = String(text || "").trim();
        if (raw === "") return [];
        const q = raw.toLowerCase();
        const d = raw.replace(/\D/g, "");
        return Link.contacts.filter(c => {
            if (String(c.name || "").toLowerCase().indexOf(q) >= 0) return true;
            return (c.numbers || []).some(n => {
                const s = String(n);
                return s.toLowerCase().indexOf(q) >= 0
                    || (d.length >= 3 && s.replace(/\D/g, "").indexOf(d) >= 0);
            });
        }).slice(0, 6);
    }

    function pickNumber(n) {
        number.text = String(n || "");
        number.cursorPosition = number.text.length;
        win.suggestions = [];
        number.forceActiveFocus();
    }

    function dtmf(digit) { win.dtmfDigits += digit }

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

    function pasteNumber() {
        const t = String(Quickshell.clipboardText || "");
        if (t !== "") { number.insert(number.cursorPosition, t); number.forceActiveFocus(); }
    }

    // ---- the window ---------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.px(8)

        Loader {
            source: "CallStatusHeader.qml"
            Layout.fillWidth: true
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            Repeater {
                model: win.tabs
                Choice {
                    required property var modelData
                    text: modelData[1]
                    selected: win.tab === modelData[0]
                    onClicked: win.tab = modelData[0]
                }
            }
        }

        Flickable {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: stack.implicitHeight
            ColumnLayout {
                id: stack
                width: body.width
                spacing: Theme.px(10)

                // ---- Calls: pad on the left, history on the right ---------------
                ColumnLayout {
                    visible: win.tab === "calls"
                    Layout.fillWidth: true
                    spacing: Theme.px(12)
                    GridLayout {
                        Layout.fillWidth: true
                        columns: win.compact ? 1 : 2
                        columnSpacing: Theme.px(16)
                        rowSpacing: Theme.px(12)

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: win.compact ? body.width : (body.width - Theme.px(16)) / 2
                            Layout.alignment: Qt.AlignTop
                            spacing: Theme.px(8)

                            // ---- the call in progress -----------------------------
                            // shani-shell rings the call; this is the shell's own live
                            // view, with Mute/Speaker on the bridge's callctl verb.
                            Glass {
                                visible: win.inCall
                                Layout.fillWidth: true
                                solid: true
                                ColumnLayout {
                                    anchors { fill: parent; margins: Theme.px(10) }
                                    spacing: Theme.px(6)
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
                                    Picks {
                                        label: Tr.t("Where the sound goes")
                                        options: [
                                            { label: Tr.t("This computer"), value: "pc" },
                                            { label: Tr.t("The phone"), value: "phone" }
                                        ]
                                        current: PhoneTools.audio.where === "phone" ? "phone" : "pc"
                                        onPicked: v => { PhoneTools.audioWhere(v); if (win.inCall) Modem.setSpeaker(v === "pc"); }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(6)
                                        RoundAction {
                                            text: Tr.t("Mute")
                                            fill: Theme.accent
                                            width: Theme.px(64); height: Theme.px(64)
                                            isOn: Modem.muted
                                            onClicked: Modem.setMute(!Modem.muted)
                                        }
                                        RoundAction {
                                            text: Tr.t("Speaker")
                                            fill: Theme.accent
                                            width: Theme.px(64); height: Theme.px(64)
                                            isOn: Modem.speaker
                                            onClicked: Modem.setSpeaker(!Modem.speaker)
                                        }
                                        RoundAction {
                                            text: Tr.t("Hang up")
                                            fill: Theme.danger
                                            width: Theme.px(64); height: Theme.px(64)
                                            onClicked: Modem.hangup()
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(6)
                                        Button {
                                            Layout.fillWidth: true
                                            text: win.held ? Tr.t("Resume") : Tr.t("Hold")
                                            checked: win.held
                                            onClicked: { win.held = !win.held; Modem.callctl("hold", win.held); }
                                        }
                                        Button {
                                            Layout.fillWidth: true
                                            text: Tr.t("Keypad")
                                            checked: win.showDtmf
                                            onClicked: win.showDtmf = !win.showDtmf
                                        }
                                        Button {
                                            Layout.fillWidth: true
                                            text: Tr.t("Swap")
                                            enabled: Modem.waitingCall !== null
                                            onClicked: Modem.callctl("swap")
                                        }
                                        Button {
                                            Layout.fillWidth: true
                                            text: Tr.t("End")
                                            kind: "danger"
                                            onClicked: Link.hangup()
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: win.dtmfDigits !== ""
                                        text: win.dtmfDigits
                                        color: Theme.accent
                                        font.family: Theme.font
                                        font.pixelSize: Theme.px(12) * Theme.fontScale
                                    }
                                    Loader {
                                        visible: win.showDtmf
                                        source: "DialPad.qml"
                                        Layout.alignment: Qt.AlignHCenter
                                        onLoaded: {
                                            item.compactKeys = true;
                                            item.digitHandler = digit => win.dtmf(digit);
                                            item.longHandler = () => win.dtmf("+");
                                        }
                                    }
                                }
                            }

                            // a second call arrived: keep the first one up
                            Glass {
                                visible: Modem.waitingCall !== null
                                Layout.fillWidth: true
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

                            Text {
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
                                label: Tr.t("A number")
                                Accessible.name: Tr.t("A number")
                                onTextChanged: { win.suggestions = win.matchesFor(text); Link.match(text); }
                                onAccepted: win.call()
                                Component.onCompleted: input.font.pixelSize = Theme.px(24) * Theme.fontScale
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: win.suggestions.length > 0
                                spacing: Theme.px(2)
                                Repeater {
                                    model: win.suggestions
                                    ListRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        icon: "contact-new"
                                        title: modelData.name || Tr.t("Contact")
                                        subtitle: (modelData.numbers || []).join(" · ")
                                        selected: false
                                        onClicked: win.pickNumber((modelData.numbers || [])[0])
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(6)
                                Button {
                                    text: Tr.t("Paste")
                                    flat: true
                                    onClicked: win.pasteNumber()
                                }
                                Button {
                                    text: Tr.t("Delete")
                                    flat: true
                                    enabled: number.text.length > 0
                                    onClicked: win.deleteDigit()
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Tr.t("Line") + ": " + (win.line || Tr.t("None"))
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
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

                            Loader {
                                source: "DialPad.qml"
                                Layout.alignment: Qt.AlignHCenter
                                onLoaded: {
                                    item.digitHandler = digit => { number.insert(number.cursorPosition, digit); number.forceActiveFocus(); };
                                    item.longHandler = () => { number.insert(number.cursorPosition, "+"); number.forceActiveFocus(); };
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(8)
                                RoundAction {
                                    text: Tr.t("Call")
                                    fill: Theme.success
                                    enabled: number.text.trim() !== ""
                                    onClicked: win.call()
                                }
                                RoundAction {
                                    text: Tr.t("End")
                                    fill: Theme.danger
                                    visible: win.inCall
                                    enabled: win.inCall
                                    onClicked: Link.hangup()
                                }
                                Item { Layout.fillWidth: true }
                            }

                            // No line is normal, not an error: offer the two ways in.
                            ColumnLayout {
                                visible: !win.lineReady
                                Layout.fillWidth: true
                                spacing: Theme.px(6)
                                Text {
                                    Layout.fillWidth: true
                                    text: Tr.t("No line is ready yet")
                                    color: Theme.dim
                                    wrapMode: Text.Wrap
                                    font.family: Theme.font
                                    font.pixelSize: Theme.px(11) * Theme.fontScale
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(6)
                                    Button {
                                        Layout.fillWidth: true
                                        text: Tr.t("Connect a phone")
                                        onClicked: Ui.openSettings("devices")
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        text: Tr.t("Set up the landline")
                                        onClicked: Ui.openSettings("phone")
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: Link.note !== ""
                                text: Link.note
                                color: Theme.text
                                wrapMode: Text.Wrap
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                        }

                        // ---- the history ------------------------------------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: win.compact ? body.width : (body.width - Theme.px(16)) / 2
                            Layout.alignment: Qt.AlignTop
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
                                Layout.preferredHeight: Math.max(Theme.px(220), Theme.px(56) * Math.min(5, count))
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
                }

                Loader {
                    source: "MusicTab.qml"
                    visible: win.tab === "music"
                    Layout.fillWidth: true
                }
                Loader {
                    source: "FilesTab.qml"
                    visible: win.tab === "files"
                    Layout.fillWidth: true
                }
                Loader {
                    source: "RemoteTab.qml"
                    visible: win.tab === "remote"
                    Layout.fillWidth: true
                }
            }
        }
    }
}
