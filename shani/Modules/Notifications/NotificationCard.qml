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
    // Enhanced card effects (noctalia-inspired): subtle glow on critical notifications and popups
    // Note: MultiEffect is available through QtQuick.Effects when enabled
    property var notification
    property bool popup: false
    // privacy mode (Settings > Notifications): the app is named, the message is not
    readonly property bool hideContent: Settings.data.notifHideContent && !critical
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
    readonly property string picture: notification && notification.image && !hideContent ? notification.image : ""
    // Shani Link's call/text notifications arrive here with their buttons
    // already on them - missed_call.py posts "Call back" / "Message",
    // incoming_call.py posts Answer / Decline, map_notify.py offers the
    // inline Reply field - and NotificationCard renders every action
    // generically below, so the panel needs nothing of its own.
    // TODO (verified trivial path): no panel buttons to add - the buttons
    // come from Shani Link's notify path (dev.shani.Link) and flow through
    // the NotificationServer above; only the SIM modem's texts are posted
    // by this shell (Services/Modem.qml, Reply / Copy-code via notify-send).
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

    function activate() {
        const def = root.notification.actions.find(a => a.identifier === "default");
        if (def)
            def.invoke({ notificationId: root.notification ? root.notification.id : null,
                         appName: root.notification ? (root.notification.appName || "") : "" });
        // and the app it came from comes forward (an app that raises itself
        // on the default action loses nothing; one that doesn't is shown)
        const w = Niri.windowOfApp(root.notification.desktopEntry, root.notification.appName);
        if (w)
            Niri.focusWin(w);
        if (root.popup)
            root.done();
    }
    HoverHandler { id: hover }
    DragHandler {
        id: swipe
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        onTranslationChanged: slide.x = translation.x
        onActiveChanged: {
            if (active)
                return;
            if (Math.abs(slide.x) > root.width / 3) {
                root.notification.dismiss();
                root.done();
            } else {
                slide.x = 0;
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: root.notification && root.notification.actions.some(a => a.identifier === "default") ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.activate()
        // the card itself is a button to a screen reader: open it, as a click does
        Accessible.role: Accessible.Button
        Accessible.name: root.notification ? root.notification.summary : ""
        Accessible.onPressAction: root.activate()
    }
    // keyboard and controller: Enter opens it (its default action), Delete dismisses it
    KeyFocus {
        name: root.notification ? root.notification.summary : ""
        radius: Theme.radiusLarge
        onActivated: root.activate()
        Keys.onDeletePressed: root.done()
    }

    // critical: a red edge down the left
    Rectangle {
        visible: root.critical
        x: 0
        y: 14
        width: 3
        height: Math.max(0, parent.height - 28)
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
                    text: root.hideContent ? Tr.t("Notification") : (root.notification ? root.notification.summary : "")
                    color: root.hideContent ? Theme.dim : Theme.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.fontScale
                    font.weight: Font.DemiBold
                    font.italic: root.hideContent
                }
                Text {
                    Layout.fillWidth: true
                    visible: !root.hideContent && text !== ""
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

        // suggested replies (SmartReplies: Chronoa writes three), one click sends one
        Flow {
            Layout.fillWidth: true
            spacing: 6
            visible: !root.hideContent && root.notification && root.notification.hasInlineReply && replies.length > 0
            readonly property var replies: root.notification ? SmartReplies.forId(root.notification.id) : []
            Component.onCompleted: if (root.notification && !root.hideContent) SmartReplies.suggest(root.notification)
            Repeater {
                model: parent.replies
                Choice {
                    required property string modelData
                    text: modelData
                    onClicked: {
                        root.notification.sendInlineReply(modelData);
                        root.done();
                    }
                }
            }
        }
        // inline reply, for apps that offer it (messaging)
        TextField {
            Layout.fillWidth: true
            visible: !root.hideContent && root.notification && root.notification.hasInlineReply
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
            visible: !root.hideContent && (root.actions.length > 0 || root.more)
            implicitHeight: 34
            radius: 12
            color: "transparent"
            RowLayout {
                anchors.fill: parent
                spacing: 2
                Repeater {
                    model: root.actions.map(a => ({ text: a.text, run: () => a.invoke({ notificationId: root.notification ? root.notification.id : null, appName: root.notification ? (root.notification.appName || "") : "" }) }))
                        .concat(!root.more ? []
                        : (root.critical ? [] : [{ text: Tr.t("Snooze"), run: () => Notifs.snooze(root.notification, Settings.data.snoozeMinutes || 60) }])
                        .concat(root.critical || !root.notification || !root.notification.appName ? []
                            : [{ text: Notifs.isSilenced(root.notification.appName) ? Tr.t("Pop up again") : Tr.t("No pop-ups"),
                                 name: (Notifs.isSilenced(root.notification.appName) ? Tr.t("Let %1 pop up again") : Tr.t("No pop-ups from %1")).arg(root.notification.appName),
                                 run: () => Notifs.setSilenced(root.notification.appName, !Notifs.isSilenced(root.notification.appName)) }])
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
                        // the action may already have closed this card (and this handler's context)
                        Accessible.onPressAction: { const keep = !!modelData.keep; modelData.run(); if (!keep && typeof root !== "undefined" && root) root.done(); }
                        MouseArea {
                            id: pill
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const keep = !!parent.modelData.keep;
                                parent.modelData.run();
                                // the action may already have closed this card (and this handler's context)
                                if (!keep && typeof root !== "undefined" && root)
                                    root.done();
                            }
                        }
                        KeyFocus {
                            name: parent.modelData.name || parent.modelData.text
                            radius: 0
                            // the action can end the notification (and this card) as it runs: what is needed is taken first
                            onActivated: { const card = root, m = parent.modelData; m.run(); if (!m.keep && card) card.done(); }
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
