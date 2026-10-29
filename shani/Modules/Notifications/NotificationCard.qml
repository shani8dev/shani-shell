// One notification: an avatar (the sender's picture, else the app's icon, else
// its initial), "App · 5 min", the summary and body, the app's actions as one
// joined row — with Snooze and "Ask Chronoa" (hand it to the assistant to
// summarise, act on or reply to). A popup shows the time it has left as a thin
// line along its foot; critical ones carry a red edge and do not leave alone.
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
    property real life: 1                // a popup's time left, 1 → 0 (Popups drives it)
    property bool more: false            // Snooze and Ask Chronoa shown ("⋯" pressed)
    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    readonly property string appName: notification ? (notification.appName || "Notification") : ""
    readonly property string appIcon: {
        const n = notification;
        if (!n)
            return "";
        if (n.appIcon)
            return n.appIcon.startsWith("/") || n.appIcon.indexOf("://") > 0 ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
        const e = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null;
        return e && e.icon ? Quickshell.iconPath(e.icon, true) : "";
    }
    // a theme with only the symbolic one (Adwaita's battery-level-10): drawn tinted
    readonly property string appSymbolic: notification && notification.appIcon && appIcon === ""
        && Quickshell.iconPath(notification.appIcon + "-symbolic", true) !== "" ? notification.appIcon : ""
    readonly property string picture: notification && notification.image ? notification.image : ""
    readonly property var actions: notification ? notification.actions.filter(a => a.identifier !== "default") : []
    signal done()

    radius: Theme.radiusLarge
    implicitHeight: body.implicitHeight + 28
    border.color: critical ? Theme.alpha(Theme.red, 0.6) : Theme.stroke
    strong: popup

    // "now", "5 min", "2 h", then the time
    property double now: Date.now()
    Timer { interval: 30000; running: root.visible; repeat: true; onTriggered: root.now = Date.now() }
    readonly property string age: {
        const t = notification ? Notifs.arrived[notification.id] : 0;
        if (!t)
            return "";
        const m = Math.floor((now - t) / 60000);
        return m < 1 ? "now" : m < 60 ? m + " min" : m < 24 * 60 ? Math.floor(m / 60) + " h" : Qt.formatDateTime(new Date(t), "d MMM");
    }

    // a popup slides in from the edge it lives on
    transform: Translate { id: slide }
    Component.onCompleted: if (popup) slideIn.start()
    ParallelAnimation {
        id: slideIn
        // in from the screen edge, settling on the emphasized curve
        NumberAnimation { target: slide; property: "x"; from: 90; to: 0; duration: Theme.animEnter; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized }
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Theme.animEnter * 0.5 }
    }

    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        cursorShape: root.notification && root.notification.actions.some(a => a.identifier === "default") ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            const def = root.notification.actions.find(a => a.identifier === "default");
            if (def)
                def.invoke();
            if (root.popup)
                root.done();
        }
    }

    // critical: a red edge down the left
    Rectangle {
        visible: root.critical
        x: 0
        y: 14
        width: 3
        height: parent.height - 28
        radius: 2
        color: Theme.red
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // the avatar: a sender's picture with the app as a badge, the app's
            // icon on a soft tile, or the app's initial
            Item {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 40
                implicitHeight: 40
                ClippingRectangle {
                    anchors.fill: parent
                    radius: root.picture ? 20 : 12
                    color: root.appIcon && !root.picture ? Theme.hover : Theme.accentSoft
                    Image {
                        anchors.fill: parent
                        visible: root.picture !== ""
                        source: root.picture
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(80, 80)
                    }
                    IconImage {
                        anchors.centerIn: parent
                        visible: !root.picture && root.appIcon !== ""
                        implicitSize: 26
                        source: root.picture ? "" : root.appIcon
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: !root.picture && root.appSymbolic !== ""
                        name: root.appSymbolic
                        size: 22
                        color: Theme.text
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !root.picture && root.appIcon === "" && root.appSymbolic === ""
                        text: root.appName.charAt(0).toUpperCase()
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    visible: root.picture !== "" && root.appIcon !== ""
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -3
                    width: 20
                    height: 20
                    radius: 10
                    color: Theme.glassStrong
                    border.width: 1
                    border.color: Theme.stroke
                    IconImage { anchors.centerIn: parent; implicitSize: 14; source: root.picture ? root.appIcon : "" }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: (root.showApp ? root.appName : "") + (root.showApp && root.age ? "  ·  " : "") + root.age
                        color: Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                    }
                    // more: Snooze and Ask Chronoa (in the header, not a row of their own)
                    IconButton {
                        icon: "view-more"
                        size: 22
                        on: root.more
                        opacity: hover.hovered || root.more ? 1 : 0.55
                        Accessible.name: Tr.t("More actions")
                        onClicked: root.more = !root.more
                    }
                    // close: always there to a screen reader and a keyboard, clearer on hover
                    IconButton {
                        icon: "window-close"
                        size: 22
                        opacity: hover.hovered || root.critical ? 1 : 0.55
                        Accessible.name: Tr.t("Dismiss")
                        onClicked: {
                            root.notification.dismiss();
                            root.done();
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.notification ? root.notification.summary : ""
                    color: Theme.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.notification ? root.notification.body : ""
                    textFormat: Text.StyledText
                    color: Theme.dim
                    linkColor: Theme.accent
                    wrapMode: Text.Wrap
                    maximumLineCount: root.popup ? 3 : 6
                    elide: Text.ElideRight
                    lineHeight: 1.1
                    font.family: Theme.font
                    font.pixelSize: 12.5 * Theme.fontScale
                    onLinkActivated: link => Qt.openUrlExternally(link)
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

        // the actions, one joined row: the app's own, and - after "⋯" in the
        // header (a tap, not a hover: touch has none) - Snooze and Ask Chronoa;
        // no row at all for a notification with nothing to do
        ClippingRectangle {
            Layout.fillWidth: true
            visible: root.actions.length > 0 || root.more
            implicitHeight: 34
            radius: 12
            color: "transparent"
            RowLayout {
                anchors.fill: parent
                spacing: 2
                Repeater {
                    model: root.actions.map(a => ({ text: a.text, run: () => a.invoke() }))
                        .concat(!root.more ? []
                        : (root.critical ? [] : [{ text: Tr.t("Snooze"), run: () => Notifs.snooze(root.notification, 60) }])
                        .concat([{ text: Tr.t("Ask Chronoa"), run: () => {
                            const n = root.notification;
                            Chronoa.ask("About this notification from " + (n.appName || "an app") + ": “" + n.summary
                                + (n.body ? " — " + n.body.replace(/<[^>]*>/g, "") : "") + "”. What should I do?");
                        } }]))
                    Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: !modelData.narrow
                        Layout.preferredWidth: modelData.narrow ? 44 : -1
                        Layout.fillHeight: true
                        color: pill.pressed ? Theme.pressed : pill.containsMouse ? Theme.alpha(Theme.accent, 0.22) : (index === 0 && root.actions.length > 0 ? Theme.accentSoft : Theme.hover)
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.modelData.text
                            color: index === 0 && root.actions.length > 0 ? Theme.accent : Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12 * Theme.fontScale
                            font.weight: Font.Medium
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name || modelData.text
                        Accessible.onPressAction: { modelData.run(); if (!modelData.keep) root.done(); }
                        MouseArea {
                            id: pill
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                parent.modelData.run();
                                if (!parent.modelData.keep)
                                    root.done();
                            }
                        }
                    }
                }
            }
        }
    }

    // a popup's time left
    Rectangle {
        visible: root.popup && !root.critical
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: 1
        anchors.leftMargin: Theme.radiusLarge
        width: (parent.width - 2 * Theme.radiusLarge) * root.life
        height: 2
        radius: 1
        color: Theme.alpha(Theme.accent, 0.7)
    }
}
