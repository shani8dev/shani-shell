// Mail: an IMAP reader (or MailHog, for development). Four panes — the
// folders, the message list, the message being read, and a small compose form.
// bridge/mail.py does the talking; the window is only a view.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Mail"
    visible: Ui.mail
    onGone: Ui.mail = false
    implicitWidth: Theme.px(1080)
    implicitHeight: Theme.px(680)

    property bool starred: (Mail.messages.find(m => m.uid === Mail.openUid) || {}).starred || false

    function saveAttachment(index, name) {
        FilePicker.open({
            mode: "save",
            title: Tr.t("Save attachment"),
            defaultName: name || "attachment",
            onPicked: paths => { if (paths && paths.length) Mail.saveAttachment(Mail.openUid, index, paths[0]); }
        });
    }

    // status note (send result, server errors)
    Text {
        anchors { top: parent.top; right: parent.right; margins: Theme.px(12) }
        z: 20
        visible: Mail.note !== ""
        text: Mail.note
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
        Timer { interval: 5000; onTriggered: Mail.note = ""; running: parent.visible }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(10)
        spacing: Theme.px(10)

        // ---- folders --------------------------------------------------------
        Rectangle {
            Layout.preferredWidth: Theme.px(200)
            Layout.fillHeight: true
            radius: Theme.radius
            color: Theme.alpha(Theme.text, 0.035)
            border.width: 1
            border.color: Theme.stroke

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(10)
                spacing: Theme.px(8)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Text { text: Tr.t("Mail"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(14) * Theme.fontScale; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    IconButton { icon: "view-refresh"; tip: Tr.t("Refresh"); size: Theme.px(26); on: Mail.busy; onClicked: Mail.refresh() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    TextField {
                        id: toField
                        Layout.fillWidth: true
                        placeholder: Tr.t("To…")
                    }
                    Button { text: Tr.t("Write"); enabled: toField.text.trim() !== ""; onClicked: { compose.visible = true; compose.to = toField.text.trim(); toField.text = "" } }
                }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Search the mail…")
                    onAccepted: Mail.search(text.trim())
                    onTextChanged: if (text.trim() === "" && Mail.query !== "") Mail.search("")
                }
                ListView {
                    id: folderList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: Mail.folders
                    delegate: ListRow {
                        required property var modelData
                        width: ListView.view.width
                        icon: modelData.unread > 0 ? "mail-unread" : "mail-read"
                        title: modelData.name
                        subtitle: modelData.unread > 0 ? Tr.t("%1 unread", modelData.unread) : ""
                        selected: Mail.folder === modelData.name
                        onClicked: Mail.open(modelData.name)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: Mail.folders.length === 0 && !Mail.busy
                    text: Mail.kind === "imap" ? Tr.t("No account set up yet") : Tr.t("No mail yet")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }

        // ---- the message list -----------------------------------------------
        ColumnLayout {
            Layout.preferredWidth: Theme.px(300)
            Layout.fillHeight: true
            spacing: Theme.px(4)

            Text {
                Layout.fillWidth: true
                text: Mail.folder
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(13) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: Mail.messages
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: ListRow {
                    required property var modelData
                    width: ListView.view.width
                    icon: modelData.unread ? "mail-unread" : "mail-read"
                    title: modelData.subject
                    subtitle: Mail.when(modelData.date) + (modelData.from ? "  ·  " + modelData.from : "")
                    selected: Mail.openUid === modelData.uid
                    onClicked: Mail.read(modelData.uid)
                }
            }
            Text {
                Layout.fillWidth: true
                visible: Mail.messages.length === 0
                text: Tr.t("Nothing in this folder")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
        }

        // ---- the message being read -----------------------------------------
        Flickable {
            id: reader
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: body.height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: body
                width: reader.width
                spacing: Theme.px(10)

                Text {
                    Layout.fillWidth: true
                    visible: Mail.subject === ""
                    text: Tr.t("Pick a message")
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
                Text {
                    Layout.fillWidth: true
                    visible: Mail.subject !== ""
                    text: Mail.subject
                    color: Theme.text
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: Theme.px(20) * Theme.fontScale
                    font.weight: Font.DemiBold
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: Mail.from !== ""
                    text: Mail.from
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                Text {
                    Layout.fillWidth: true
                    visible: Mail.body !== "" && !Mail.showHtml
                    text: Mail.body
                    color: Theme.text
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                }
                // the message as it was sent: Qt's TextDocument renders a subset
                // of HTML, and the bridge has already taken out everything that
                // reaches outside the message (scripts, remote images, handlers)
                TextDocument {
                    Layout.fillWidth: true
                    visible: Mail.showHtml && Mail.html !== ""
                    textFormat: TextEdit.RichText
                    text: Mail.html
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: Mail.html !== ""
                    spacing: Theme.px(6)
                    Button {
                        text: Tr.t("Plain text")
                        flat: true
                        visible: Mail.showHtml
                        onClicked: Mail.showHtml = false
                    }
                    Button {
                        text: Tr.t("Original formatting")
                        flat: true
                        visible: !Mail.showHtml
                        onClicked: Mail.showHtml = true
                    }
                    Choice {
                        text: Tr.t("Load images")
                        selected: Mail.remoteImages
                        onClicked: Mail.setRemoteImages(!Mail.remoteImages)
                    }
                    Item { Layout.fillWidth: true }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Mail.attachments.length > 0
                    spacing: Theme.px(2)
                    Repeater {
                        model: Mail.attachments
                        ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: "mail-attachment"
                            title: modelData.name || Tr.t("attachment")
                            subtitle: modelData.size > 0 ? Mail.size(modelData.size) : (modelData.type || "")
                            interactive: false
                            IconButton {
                                icon: "document-save"
                                size: Theme.px(22)
                                tip: Tr.t("Save attachment")
                                onClicked: win.saveAttachment(index, modelData.name)
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: Mail.openUid !== ""
                    spacing: Theme.px(6)
                    Button {
                        text: Tr.t("Reply")
                        flat: true
                        enabled: Mail.from !== ""
                        onClicked: win.startCompose(Mail.from, win.replySubject(), win.quotedBody())
                    }
                    Button {
                        text: Tr.t("Forward")
                        flat: true
                        onClicked: win.startCompose("", "Fwd: " + Mail.subject,
                            "\n\n---------- Forwarded message ----------\nFrom: " + Mail.from + "\nSubject: " + Mail.subject + "\n\n" + Mail.body)
                    }
                    Button {
                        text: Tr.t("Unread")
                        flat: true
                        onClicked: Mail.markUnread(Mail.openUid)
                    }
                    Button {
                        text: win.starred ? Tr.t("Unstar") : Tr.t("Star")
                        flat: true
                        checked: win.starred
                        onClicked: Mail.flag(Mail.openUid, "\\Flagged", !win.starred)
                    }
                    Button {
                        text: Tr.t("Archive")
                        flat: true
                        onClicked: Mail.archive(Mail.openUid)
                    }
                    Button {
                        text: Tr.t("View source")
                        flat: true
                        onClicked: Mail.viewSource(Mail.openUid)
                    }
                    Button {
                        text: Tr.t("Delete")
                        kind: "danger"
                        flat: true
                        onClicked: Mail.remove(Mail.openUid)
                    }
                    Item { Layout.fillWidth: true }
                }
                Item { Layout.preferredHeight: 20 }
            }
        }
    }

    // ---- compose ------------------------------------------------------------
    function startCompose(to, subject, body) {
        compose.visible = true;
        compose.to = to;
        toBox.text = to;
        ccBox.text = "";
        bccBox.text = "";
        subBox.text = subject;
        bodyBox.text = body;
        toBox.forceActiveFocus();
    }
    function replySubject() {
        const s = String(Mail.subject || "");
        return /^re:/i.test(s.trim()) ? s : "Re: " + s;
    }
    function quotedBody() {
        return "\n\nOn " + Mail.when(Mail.date) + ", " + Mail.from + " wrote:\n> "
            + String(Mail.body || "").replace(/\n/g, "\n> ");
    }
    Rectangle {
        id: compose
        visible: false
        property string to: ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, Theme.px(560))
        implicitHeight: col.implicitHeight + 40
        radius: Theme.radiusLarge
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.stroke

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: Theme.px(8)

            Text { text: Tr.t("New message"); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(16) * Theme.fontScale; font.weight: Font.DemiBold }
            TextField { id: toBox; Layout.fillWidth: true; placeholder: Tr.t("To…"); text: compose.to }
            TextField { id: ccBox; Layout.fillWidth: true; placeholder: Tr.t("Cc…") }
            TextField { id: bccBox; Layout.fillWidth: true; placeholder: Tr.t("Bcc…") }
            TextField { id: subBox; Layout.fillWidth: true; placeholder: Tr.t("Subject…") }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(160)
                TextArea { id: bodyBox; placeholderText: Tr.t("Write here…"); wrapMode: TextArea.Wrap; textFormat: Text.PlainText }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button {
                    text: Tr.t("Send")
                    kind: "primary"
                    enabled: toBox.text.trim() !== "" && subBox.text.trim() !== ""
                    onClicked: {
                        Mail.send(toBox.text.trim(), subBox.text, bodyBox.text,
                                  ccBox.text.trim(), bccBox.text.trim());
                        compose.visible = false; compose.to = "";
                        ccBox.text = ""; bccBox.text = ""; subBox.text = ""; bodyBox.text = "";
                    }
                }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: { compose.visible = false; compose.to = ""; ccBox.text = ""; bccBox.text = "" } }
            }
        }
    }

    // ---- the message as it arrived -----------------------------------------
    Rectangle {
        id: sourceView
        visible: Mail.source !== ""
        z: 30
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, Theme.px(760))
        height: Math.min(parent.height - 80, Theme.px(520))
        radius: Theme.radiusLarge
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.stroke

        ColumnLayout {
            anchors { fill: parent; margins: Theme.px(16) }
            spacing: Theme.px(8)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Tr.t("Message source")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                IconButton { icon: "window-close"; tip: Tr.t("Close"); size: Theme.px(24); onClicked: Mail.source = "" }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    readOnly: true
                    text: Mail.source
                    wrapMode: TextArea.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.mono
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
        }
    }
}