// Messages: the phone's conversations, read and answered from the keyboard.
// The list is one row per conversation, the newest first; opening one shows
// the thread and the reply box. Sending is a real send — the button says so.
//
// bridge/link.py does the talking (phone.phone: GSConnect, KDE Connect, or
// plain Bluetooth through MAP); the window is only a view.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Messages"
    visible: Ui.messages
    onGone: Ui.messages = false
    implicitWidth: Theme.px(860)
    implicitHeight: Theme.px(620)

    property string pendingNumber: ""   // a requested conversation, matched once messages arrive
    property string retryText: ""       // last send's text, kept until the bridge replies
    property string search: ""          // conversation filter, name / number / last line

    onVisibleChanged: if (visible) {
        pendingNumber = Ui.messagesNumber.trim();
        Ui.messagesPending = pendingNumber;
        Ui.messagesNumber = "";
        Link.openDevice("");
        win.tryPendingNumber();
    }

    // a number from the launcher, a notification's "Reply" or the phone tile:
    // open its thread if there is one, otherwise a new composer addressed to it
    function tryPendingNumber() {
        if (pendingNumber === "" || !Link.messagesLoaded) return;
        const want = pendingNumber;
        pendingNumber = "";
        const hit = Link.messages.find(m => Link.matchesParty(m, want));
        if (hit) Link.showThread(hit.thread, hit.name || hit.number);
        else Link.startConversation(want);
        // a notification's "Reply" should land in the composer, not on a row
        Qt.callLater(() => reply.forceActiveFocus());
    }
    function copyText(value) {
        const s = String(value || "").trim();
        if (s) Quickshell.clipboardText = s;
    }

    Connections {
        target: Link
        function onMessagesLoadedChanged() { if (Link.messagesLoaded) win.tryPendingNumber(); }
        // a thread change or a new message: show the end of the conversation,
        // not the first lines of a thread opened hours ago
        function onOpenThreadChanged() {
            if (win.retryText !== "" && Link.openThread === "") win.retryText = "";   // a send landed
            if (Link.openThread !== "") Qt.callLater(() => thread.positionViewAtEnd());
        }
        // a failed send keeps its text in the composer, so Send is a retry
        function onNoteChanged() {
            if (win.retryText !== "" && Link.note !== "" && Link.note !== Tr.t("Text sent"))
                reply.text = win.retryText;
        }
    }

    // Escape unwinds the search, then the thread, then the window; Ctrl+F
    // reaches the same search field Contacts and Mail put there.
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: {
            if (win.search !== "") { searchBox.text = ""; win.search = ""; }
            else if (Link.openThread !== "") Link.openDevice(Link.phone ? Link.phone.id : "");
            else Ui.messages = false;
        }
        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F) {
                searchBox.forceActiveFocus(); e.accepted = true;
            }
        }
    }

    // ---- the conversations --------------------------------------------------
    TextField {
        id: searchBox
        objectName: "messageSearch"
        anchors { top: parent.top; left: parent.left; margins: Theme.px(12) }
        width: Theme.px(256)
        placeholder: Tr.t("Search conversations")
        label: Tr.t("Search conversations")
        onTextChanged: win.search = text
    }
    ListView {
        id: list
        anchors { top: searchBox.bottom; topMargin: Theme.px(6); bottom: parent.bottom; left: parent.left; leftMargin: Theme.px(12) }
        width: Theme.px(280)
        clip: true
        spacing: Theme.px(2)
        model: Link.visibleConversations(win.search)
        Accessible.role: Accessible.List
        Accessible.name: Tr.t("Conversations")
        delegate: ListRow {
            required property var modelData
            width: ListView.view.width
            icon: "mail-unread"
            title: modelData.name || modelData.number || Tr.t("Unknown")
            subtitle: (modelData.unread ? "● " : "") + modelData.text
            trailing: modelData.unread ? Tr.t("Unread") : ""
            selected: Link.openThread === modelData.thread
            onClicked: Link.showThread(modelData.thread, modelData.name || modelData.number)
            IconButton {
                size: Theme.px(24)
                icon: "call-start"
                accessibleName: Tr.t("Call %1", modelData.name || modelData.number || "")
                onClicked: Link.dial(modelData.number || "")
            }
            IconButton {
                size: Theme.px(24)
                icon: "edit-copy"
                accessibleName: Tr.t("Copy number of %1", modelData.name || modelData.number || "")
                onClicked: win.copyText(modelData.number)
            }
        }
        EmptyState {
            anchors.centerIn: parent
            width: parent.width - Theme.px(24)
            visible: list.count === 0
            icon: !Link.messagesLoaded ? "view-refresh" : !Link.phone ? "call-start"
                : win.search !== "" ? "edit-find" : "mail-unread"
            title: !Link.messagesLoaded ? Tr.t("Loading conversations…")
                : !Link.phone ? Tr.t("No phone is connected")
                : win.search !== "" ? Tr.t("Nothing matches %1", win.search)
                : Tr.t("No conversations")
            subtitle: !Link.messagesLoaded ? Tr.t("Waiting for the phone to answer")
                : !Link.phone ? Tr.t("Pair a phone in Settings › Phone")
                : win.search !== "" ? Tr.t("Try a name, a number or a word from the last message")
                : Tr.t("Messages you send and receive will appear here")
            actionText: win.search !== "" ? Tr.t("Clear search") : ""
            onAction: { searchBox.text = ""; win.search = ""; }
        }
    }

    // ---- one conversation ---------------------------------------------------
    ColumnLayout {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; margins: Theme.px(12) }
        width: win.width - Theme.px(320)
        spacing: Theme.px(8)

        RowLayout {
            Layout.fillWidth: true
            Text {
                // openDevice() clears the thread but not its name: do not keep a
                // closed conversation's title above an empty composer
                text: Link.openThread !== "" && Link.threadName !== "" ? Link.threadName : ""   // the window says "Messages"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(15) * Theme.fontScale
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: Link.phoneName !== ""
                text: Link.phoneName
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }

        ListView {
            id: thread
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.px(6)
            model: Link.thread
            Accessible.role: Accessible.List
            Accessible.name: Tr.t("Conversation")
            onCountChanged: if (count > 0) Qt.callLater(() => thread.positionViewAtEnd())
            delegate: RowLayout {
                required property var modelData
                width: ListView.view.width
                // incoming on the left, sent on the right, as every messenger does
                layoutDirection: modelData.incoming ? Qt.LeftToRight : Qt.RightToLeft
                spacing: Theme.px(6)
                Rectangle {
                    implicitWidth: Math.min(implicitText.implicitWidth + Theme.px(20), thread.width * 0.72)
                    implicitHeight: implicitText.implicitHeight + Theme.px(12)
                    radius: Theme.px(10)
                    color: modelData.incoming ? Theme.hover : Theme.accent
                    Text {
                        id: implicitText
                        anchors.fill: parent
                        anchors.margins: Theme.px(6)
                        text: modelData.text
                        color: modelData.incoming ? Theme.text : Theme.accentInk
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                }
                Text {
                    text: Link.when(modelData.when)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
                Item { Layout.fillWidth: true }
            }
            EmptyState {
                anchors.centerIn: parent
                width: parent.width - Theme.px(24)
                visible: thread.count === 0 && Link.openThread !== ""
                icon: "mail-unread"
                title: Tr.t("Nothing said yet")
                subtitle: Tr.t("Write the first message below")
            }
        }

        // ---- the reply box -------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: reply
                objectName: "messageReply"
                Layout.fillWidth: true
                enabled: Link.openThread !== ""
                text: Link.draft
                onTextChanged: { if (Link.draft !== text) Link.setDraft(text); }
                placeholder: Tr.t("Write a text…")
                label: Tr.t("Message to %1").arg(Link.threadName || Tr.t("this conversation"))
                onAccepted: win.send()
            }
            Button {
                text: Tr.t("Send")
                kind: "primary"
                enabled: reply.text.trim() !== "" && Link.openThread !== ""
                onClicked: win.send()
            }
        }
        Text {
            visible: Link.sendState !== ""
            text: Link.sendState === "sending" ? Tr.t("Sending…")
                : Link.sendState === "sent" ? Tr.t("Sent")
                : Link.sendState === "error" ? Tr.t("Not sent — tap Send to retry") : ""
            color: Link.sendState === "error" ? Theme.danger : Theme.faint
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
            Accessible.role: Accessible.StatusBar
            Accessible.name: text
        }
        Text {
            visible: Link.draft !== "" && Link.sendState !== "sending"
            text: Tr.t("Draft saved for this conversation")
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: Theme.px(10) * Theme.fontScale
            Accessible.role: Accessible.StatusBar
            Accessible.name: text
        }
        Text {
            visible: Link.note !== ""
            text: Link.note
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
            Accessible.role: Accessible.StatusBar
            Accessible.name: Link.note
        }
    }

    function send() {
        const t = reply.text.trim();
        if (t === "" || Link.openThread === "") return;
        retryText = t;
        Link.send(t);
        Link.clearDraft();
    }
}
