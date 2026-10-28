// One notification: app, summary, body, image, its actions, and "Ask Chronoa"
// — hand the notification to the assistant (summarise it, act on it, reply).
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

Glass {
    id: root
    property var notification
    property bool popup: false
    property bool showApp: true          // false inside a group: the header already names the app
    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    signal done()

    implicitHeight: body.implicitHeight + 24
    border.color: critical ? Theme.alpha(Theme.red, 0.55) : Theme.stroke
    strong: popup

    MouseArea {
        anchors.fill: parent
        onClicked: {
            const def = root.notification.actions.find(a => a.identifier === "default");
            if (def)
                def.invoke();
            if (root.popup)
                root.done();
        }
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IconImage {
                visible: root.showApp
                implicitSize: 16
                source: {
                    const n = root.notification;
                    if (!n)
                        return "";
                    if (n.appIcon)
                        return n.appIcon.startsWith("/") || n.appIcon.indexOf("://") > 0 ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
                    const e = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null;
                    return e ? Quickshell.iconPath(e.icon, true) : "";
                }
            }
            Text {
                Layout.fillWidth: true
                opacity: root.showApp ? 1 : 0
                text: root.notification ? (root.notification.appName || "Notification") : ""
                color: Theme.dim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 11
            }
            IconButton {
                icon: "window-close"
                size: 22
                onClicked: {
                    root.notification.dismiss();
                    root.done();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: root.notification ? root.notification.summary : ""
                    color: Theme.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.notification ? root.notification.body : ""
                    textFormat: Text.StyledText
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    maximumLineCount: root.popup ? 3 : 6
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 12
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
            ClippingRectangle {
                visible: root.notification && root.notification.image !== ""
                implicitWidth: 48
                implicitHeight: 48
                radius: 8
                color: "transparent"
                Image {
                    anchors.fill: parent
                    source: root.notification ? root.notification.image : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
        }

        // inline reply, for apps that offer it (messaging)
        TextField {
            Layout.fillWidth: true
            visible: root.notification && root.notification.hasInlineReply
            placeholder: root.notification && root.notification.inlineReplyPlaceholder ? root.notification.inlineReplyPlaceholder : "Reply…"
            onAccepted: {
                if (text.trim() === "")
                    return;
                root.notification.sendInlineReply(text);
                text = "";
                root.done();
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.notification ? root.notification.actions.filter(a => a.identifier !== "default") : []
                Button {
                    required property var modelData
                    text: modelData.text
                    onClicked: {
                        modelData.invoke();
                        root.done();
                    }
                }
            }
            Button {
                text: "Ask Chronoa"
                onClicked: {
                    const n = root.notification;
                    Chronoa.ask("About this notification from " + (n.appName || "an app") + ": “" + n.summary
                        + (n.body ? " — " + n.body.replace(/<[^>]*>/g, "") : "") + "”. What should I do?");
                    root.done();
                }
            }
        }
    }
}
