// Messages: the phone's conversations, read and answered from the keyboard.
// The list is one row per conversation, the newest first; opening one shows
// the thread and the reply box. Sending is a real send — the button says so.
//
// bridge/link.py does the talking (shani_link.phone: GSConnect, KDE Connect, or
// plain Bluetooth through MAP); the window is only a view.
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

    onVisibleChanged: if (visible) {
        Link.openDevice("");
        // a number from the launcher, a notification's "Reply" or the phone tile
        if (Ui.messagesNumber !== "") {
            const want = Ui.messagesNumber;
            Ui.messagesNumber = "";
            const hit = Link.messages.find(m => m.number === want || (m.name || "") === want);
            if (hit) Link.showThread(hit.thread, hit.name || hit.number);
        }
    }

    // ---- the conversations --------------------------------------------------
    ListView {
        id: list
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: Theme.px(12) }
        width: Theme.px(280)
        clip: true
        spacing: Theme.px(2)
        model: Link.messages
        delegate: ListRow {
            required property var modelData
            width: ListView.view.width
            icon: "mail-unread"
            title: modelData.name || modelData.number || Tr.t("Unknown")
            subtitle: (modelData.unread ? "● " : "") + modelData.text
            selected: Link.openThread === modelData.thread
            onClicked: Link.showThread(modelData.thread, modelData.name || modelData.number)
        }
        Text {
            anchors.centerIn: parent
            visible: Link.messages.length === 0
            text: Link.placesCalls ? Tr.t("No conversations") : Tr.t("No phone is connected")
            color: Theme.dim
            wrapMode: Text.Wrap
            width: parent.width - Theme.px(30)
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font
            font.pixelSize: Theme.px(12) * Theme.fontScale
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
                text: Link.threadName || Tr.t("Messages")
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
            Text {
                anchors.centerIn: parent
                visible: Link.thread.length === 0 && Link.openThread !== ""
                text: Tr.t("Nothing said yet")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
        }

        // ---- the reply box -------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            TextField {
                id: reply
                Layout.fillWidth: true
                enabled: Link.openThread !== ""
                placeholder: Tr.t("Write a text…")
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
            visible: Link.note !== ""
            text: Link.note
            color: Theme.danger
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: Theme.px(11) * Theme.fontScale
        }
    }

    function send() {
        const t = reply.text.trim();
        if (t === "" || Link.openThread === "") return;
        Link.send(t);
        reply.text = "";
    }
}