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
                    subtitle: modelData.from
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
                    visible: Mail.body !== ""
                    text: Mail.body
                    color: Theme.text
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.font
                    font.pixelSize: Theme.px(14) * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: Mail.openUid !== ""
                    spacing: Theme.px(6)
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
            TextField { id: subBox; Layout.fillWidth: true; placeholder: Tr.t("Subject…") }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(160)
                TextArea { id: bodyBox; placeholderText: Tr.t("Write here…"); wrapMode: TextArea.Wrap; textFormat: Text.PlainText }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Button { text: Tr.t("Send"); kind: "primary"; enabled: toBox.text.trim() !== "" && subBox.text.trim() !== ""; onClicked: { Mail.send(toBox.text.trim(), subBox.text, bodyBox.text); compose.visible = false; compose.to = ""; subBox.text = ""; bodyBox.text = "" } }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); flat: true; onClicked: { compose.visible = false; compose.to = "" } }
            }
        }
    }
}