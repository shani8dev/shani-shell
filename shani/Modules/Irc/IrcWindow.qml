// IRC: a small client for the shell. The server form, the channels and their
// nicks, a timeline with unread/mention badges, and a send field. The socket
// lives in bridge/irc.py (Services/Irc keeps it across window closes).
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "IRC"
    visible: Ui.irc
    onGone: Ui.irc = false
    implicitWidth: Theme.px(1000)
    implicitHeight: Theme.px(660)

    onVisibleChanged: Irc.shown = visible
    Component.onCompleted: Irc.shown = visible

    function shownMessages() {
        return Irc.messages.filter(m => !Irc.activeChannel || m.channel === Irc.activeChannel);
    }
    function nicksFor(channel) { return Irc.nicks[channel] || []; }
    function statusText() {
        if (Irc.status === "connected") return Tr.t("Connected to %1", Irc.server);
        if (Irc.status === "connecting") return Tr.t("Connecting to %1…", Irc.server);
        if (Irc.status === "error") return Tr.t("Disconnected — %1", Irc.error || Tr.t("error"));
        return Tr.t("Not connected");
    }
    function connectClicked() {
        if (Irc.status === "disconnected" || Irc.status === "error") Irc.connect();
        else Irc.quit();
    }
    function joinClicked() {
        const ch = joinField.text.trim();
        if (!ch) return;
        Irc.join(ch);
        joinField.text = "";
    }
    function sendClicked() {
        const text = sendField.text.trim();
        if (!text || !Irc.activeChannel) return;
        Irc.say(Irc.activeChannel, text);
        sendField.text = "";
    }

    Connections {
        target: Irc
        function onMessageArrived() { Qt.callLater(() => timeline.positionViewAtEnd()); }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(10)
        spacing: Theme.px(8)

        // ---- connection form and live status ---------------------------------
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: form.implicitHeight + Theme.px(12)
            radius: Theme.radius
            color: Theme.alpha(Theme.text, 0.035)
            border.width: 1
            border.color: Theme.stroke

            RowLayout {
                id: form
                anchors.fill: parent
                anchors.margins: Theme.px(6)
                spacing: Theme.px(8)
                TextField {
                    id: serverField; objectName: "irc-server"
                    Layout.preferredWidth: Theme.px(200)
                    label: Tr.t("IRC server")
                    placeholder: Tr.t("irc.libera.chat")
                    text: Irc.server
                    onTextChanged: Irc.server = text
                    onAccepted: win.connectClicked()
                    enabled: Irc.status === "disconnected" || Irc.status === "error"
                }
                TextField {
                    id: portField; objectName: "irc-port"
                    Layout.preferredWidth: Theme.px(80)
                    label: Tr.t("Port")
                    mode: "digits"
                    text: String(Irc.port)
                    onTextChanged: Irc.port = Number(text) || 6667
                    enabled: Irc.status === "disconnected" || Irc.status === "error"
                }
                TextField {
                    id: nickField; objectName: "irc-nick"
                    Layout.preferredWidth: Theme.px(140)
                    label: Tr.t("Nickname")
                    placeholder: Tr.t("Your nickname")
                    text: Irc.nick
                    onTextChanged: Irc.nick = text
                    enabled: Irc.status === "disconnected" || Irc.status === "error"
                }
                CheckBox {
                    id: tlsBox
                    text: Tr.t("TLS")
                    checked: Irc.tls
                    onToggled: Irc.tls = checked
                    Accessible.name: Tr.t("Use TLS")
                    enabled: Irc.status === "disconnected" || Irc.status === "error"
                }
                Button {
                    id: connectButton
                    kind: "primary"
                    text: (Irc.status === "disconnected" || Irc.status === "error") ? Tr.t("Connect") : Tr.t("Disconnect")
                    onClicked: win.connectClicked()
                }
                Button {
                    id: reconnectButton
                    visible: Irc.status === "error" || Irc.status === "disconnected"
                    text: Tr.t("Reconnect")
                    onClicked: Irc.reconnect()
                }
                Item { Layout.fillWidth: true }
                Text {
                    id: statusLabel
                    text: win.statusText()
                    color: Irc.status === "connected" ? Theme.accent
                         : Irc.status === "error" ? Theme.danger : Theme.dim
                    font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }
        }

        // a failed connection is distinct from an empty channel
        Text {
            Layout.fillWidth: true
            visible: Irc.error !== ""
            text: Tr.t("IRC error: %1", Irc.error)
            color: Theme.danger; wrapMode: Text.WordWrap
            font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(8)

            // ---- channels -----------------------------------------------------
            Rectangle {
                Layout.preferredWidth: Theme.px(210)
                Layout.fillHeight: true
                radius: Theme.radius
                color: Theme.alpha(Theme.text, 0.035)
                border.width: 1; border.color: Theme.stroke
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    spacing: Theme.px(6)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        TextField {
                            id: joinField; objectName: "irc-join"
                            Layout.fillWidth: true
                            label: Tr.t("Channel")
                            placeholder: Tr.t("#channel")
                            onAccepted: win.joinClicked()
                        }
                        Button {
                            id: joinButton
                            text: Tr.t("Join")
                            enabled: joinField.text.trim() !== ""
                            onClicked: win.joinClicked()
                        }
                    }
                    ListView {
                        id: channelsView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: Irc.channels
                        delegate: Rectangle {
                            width: channelsView.width
                            implicitHeight: Theme.px(34)
                            color: modelData === Irc.activeChannel ? Theme.alpha(Theme.accent, 0.2) : "transparent"
                            radius: Theme.radiusSmall
                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData
                                + ((Irc.unread[modelData] || 0) > 0 ? ", " + Tr.t("%1 unread", Irc.unread[modelData]) : "")
                                + ((Irc.mentions[modelData] || 0) > 0 ? ", " + Tr.t("%1 mentions", Irc.mentions[modelData]) : "")
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.px(6)
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData
                                    color: Theme.text
                                    font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale
                                    font.weight: (Irc.mentions[modelData] || 0) > 0 ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: (Irc.unread[modelData] || 0) > 0
                                    implicitWidth: badge.implicitWidth + Theme.px(12)
                                    implicitHeight: Theme.px(20)
                                    radius: Theme.px(10)
                                    color: (Irc.mentions[modelData] || 0) > 0 ? Theme.danger : Theme.accent
                                    Text {
                                        id: badge; anchors.centerIn: parent
                                        text: String(Irc.unread[modelData] || 0)
                                        color: Theme.bg
                                        font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: Irc.markRead(modelData)
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: Irc.channels.length === 0
                            text: Tr.t("No channels — connect and join one")
                            color: Theme.dim; wrapMode: Text.WordWrap
                            font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                            Accessible.name: text
                        }
                    }
                }
            }

            // ---- timeline -----------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radius
                color: Theme.alpha(Theme.text, 0.02)
                border.width: 1; border.color: Theme.stroke
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    spacing: Theme.px(6)
                    ListView {
                        id: timeline
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: win.shownMessages()
                        delegate: Rectangle {
                            width: timeline.width
                            implicitHeight: row.implicitHeight + Theme.px(4)
                            color: modelData.mention ? Theme.alpha(Theme.accent, 0.16) : "transparent"
                            radius: Theme.radiusSmall
                            Accessible.role: Accessible.StaticText
                            Accessible.name: Tr.t("%1 at %2 in %3%4: %5", modelData.nick, modelData.time,
                                modelData.channel, modelData.mention ? ", mention" : "", modelData.text)
                            RowLayout {
                                id: row
                                anchors.fill: parent
                                spacing: Theme.px(6)
                                Text {
                                    text: modelData.time
                                    color: Theme.dim
                                    font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale
                                }
                                Text {
                                    text: modelData.nick
                                    color: modelData.mention ? Theme.danger : Theme.accent
                                    font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.mention ? "✱ " + modelData.text : modelData.text
                                    color: Theme.text; wrapMode: Text.WordWrap
                                    font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale
                                }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: Irc.channels.length > 0 && win.shownMessages().length === 0
                            text: Tr.t("No messages yet — say hello")
                            color: Theme.dim
                            font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                            Accessible.name: text
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: Irc.channels.length === 0
                            text: Tr.t("Connect and join a channel to start chatting")
                            color: Theme.dim; wrapMode: Text.WordWrap
                            font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                            Accessible.name: text
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)
                        TextField {
                            id: sendField; objectName: "irc-send"
                            Layout.fillWidth: true
                            label: Tr.t("Message")
                            placeholder: Tr.t("Write a message…")
                            onAccepted: win.sendClicked()
                        }
                        Button {
                            id: sendButton
                            kind: "primary"
                            text: Tr.t("Send")
                            enabled: sendField.text.trim() !== "" && Irc.activeChannel !== ""
                            onClicked: win.sendClicked()
                        }
                    }
                }
            }

            // ---- nick list ----------------------------------------------------
            Rectangle {
                Layout.preferredWidth: Theme.px(150)
                Layout.fillHeight: true
                radius: Theme.radius
                color: Theme.alpha(Theme.text, 0.035)
                border.width: 1; border.color: Theme.stroke
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
                    spacing: Theme.px(6)
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("People")
                        color: Theme.dim
                        font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: win.nicksFor(Irc.activeChannel)
                        delegate: Text {
                            width: parent ? parent.width : 0
                            text: modelData
                            color: modelData === Irc.nick ? Theme.accent : Theme.text
                            font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData
                        }
                    }
                }
            }
        }
    }
}
