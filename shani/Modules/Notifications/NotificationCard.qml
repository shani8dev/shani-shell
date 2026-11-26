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
import "../../Common/Gestures.js" as Hold

Glass {
    id: root
    // Enhanced card effects (noctalia-inspired): subtle glow on critical notifications and popups
    // Note: MultiEffect is available through QtQuick.Effects when enabled
    property var notification
    property bool popup: false
    // a finger has no hover: keep the header buttons readable on touch devices
    readonly property bool touchFirst: ["tablet", "phone", "board"].indexOf(FormFactor.focused.profile) >= 0
    // privacy mode (Settings > Notifications): the app is named, the message is not
    readonly property bool hideContent: Settings.data.notifHideContent && !critical
    property bool showApp: true          // false inside a group: the header already names the app
    property real life: 1                // a popup's time left, 1 → 0 (Popups drives it)
    property bool more: false            // Snooze and Ask Chronoa shown ("⋯" pressed)
    // a popup's countdown holds while the card is being used: the extra
    // actions or the menu are open, a reply is being typed, a finger is down
    // (touch has no hover), or a swipe is under way
    readonly property bool interacting: more || (contextMenu && contextMenu.visible)
        || (replyField && replyField.activeFocus) || tap.pressed || swipe.active
    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    readonly property string appName: notification ? (notification.appName || Tr.t("Notification")) : ""
    // Notification bodies come from arbitrary apps. Rendered as Text.PlainText,
    // Qt shows tags literally; HTML-escaping here would display "&amp;" to the user.
    function safeBody(body) { return String(body || ""); }
    function openLink(link) {
        if (/^(https?:\/\/|mailto:)/i.test(link)) Qt.openUrlExternally(link);
    }
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
    // Missed calls and texts arrive with their buttons already on them and
    // are rendered generically below. Ringing calls use the shell's own card
    // (Modules/Calls/IncomingCall.qml), not a notification.
    readonly property var actions: notification ? notification.actions.filter(a => a.identifier !== "default") : []
    signal done()

    radius: Theme.radiusLarge
    implicitHeight: body.implicitHeight + 34   // room for three wrapped body lines
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

    function dismissCard() {
        if (root.notification)
            root.notification.dismiss();
        root.done();
    }
    function openMenu(px, py) {
        if (!root.notification)
            return;
        contextMenu.x = Math.max(0, Math.min(px, root.width - contextMenu.width));
        contextMenu.y = Math.max(0, Math.min(py, root.height - contextMenu.height));
        contextMenu.visible = true;
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
                root.dismissCard();
            } else {
                slide.x = 0;
            }
        }
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // a finger has no right button: a long press asks for the menu, and the
        // click that ends it must not also open the notification
        property var held: Hold.state()
        onPressed: Hold.press(held)
        onPressAndHold: {
            if (Math.abs(swipe.translation.x) > Theme.px(8))
                return;                       // a drag is under way, not a hold
            Hold.hold(held);
            swipe.enabled = false;            // reject the drag grab while the menu is up
            root.openMenu(mouseX, mouseY);
        }
        onReleased: swipe.enabled = true
        onCanceled: swipe.enabled = true
        cursorShape: root.notification && root.notification.actions.some(a => a.identifier === "default") ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: e => {
            if (Hold.swallowed(held))
                return;
            if (contextMenu.visible) {
                contextMenu.visible = false;   // a tap outside the menu closes it
                return;
            }
            if (e.button === Qt.RightButton) {
                root.openMenu(e.x, e.y);
                return;
            }
            root.activate();
        }
        // the card itself is a button to a screen reader: open it, as a click
        // does; name the app and the urgency too, so two "New message" cards
        // are told apart and a critical one is heard as critical
        Accessible.role: Accessible.Button
        Accessible.name: root.notification
            ? (root.critical ? Tr.t("Urgent") + ", " : "")
              + (root.showApp && root.notification.appName ? root.notification.appName + ": " : "")
              + root.notification.summary
            : ""
        Accessible.onPressAction: root.activate()
    }
    // keyboard and controller: Enter opens it (its default action), Delete dismisses it
    KeyFocus {
        name: root.notification ? root.notification.summary : ""
        radius: Theme.radiusLarge
        onActivated: root.activate()
        Keys.onDeletePressed: root.dismissCard()
    }

    // a swipe reveals this backing strip: the red grows as the card slides, so
    // the dismiss action is discoverable before the card is let go
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Theme.red
        opacity: Math.abs(slide.x) / root.width
    }

    // critical: a tint as well as the red edge, so it reads as urgent at a glance
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        visible: root.critical
        color: Theme.alpha(Theme.red, 0.10)
    }
    // critical: a red edge down the left
    Rectangle {
        visible: root.critical
        x: 0
        y: 14
        width: Theme.px(3)
        height: Math.max(0, parent.height - 28)
        radius: 2
        color: Theme.red
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.px(14)
        spacing: Theme.px(10)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(12)

            // the avatar: a sender's picture with the app as a badge, the app's
            // icon on a soft tile, or the app's initial
            Item {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Theme.px(40)
                implicitHeight: Theme.px(40)
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
                        size: Theme.px(22)
                        color: Theme.text
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !root.picture && root.appIcon === "" && root.appSymbolic === ""
                        text: root.appName.charAt(0).toUpperCase()
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.px(18)
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    visible: root.picture !== "" && root.appIcon !== ""
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -3
                    width: Theme.px(20)
                    height: Theme.px(20)
                    radius: Theme.px(10)
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
                    spacing: Theme.px(6)
                    Text {
                        Layout.fillWidth: true
                        text: (root.showApp ? root.appName : "") + (root.showApp && root.age ? "  ·  " : "") + root.age
                        color: Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.type("small")
                    }
                    // critical: a word as well as the red tint, so urgency does not
                    // depend on colour alone (a11y) - distinct from the edge/tint
                    Rectangle {
                        visible: root.critical
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: urgentLabel.implicitHeight + Theme.px(6)
                        implicitWidth: urgentLabel.implicitWidth + Theme.px(12)
                        radius: Theme.px(6)
                        color: Theme.alpha(Theme.red, 0.16)
                        border.width: 1
                        border.color: Theme.alpha(Theme.red, 0.5)
                        Text {
                            id: urgentLabel
                            anchors.centerIn: parent
                            text: Tr.t("Urgent")
                            color: Theme.red
                            font.family: Theme.font
                            font.pixelSize: Theme.type("caption")
                            font.weight: Font.DemiBold
                        }
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Tr.t("Urgent")
                    }
                    // more: Snooze and Ask Chronoa (in the header, not a row of their own)
                    IconButton {
                        icon: "view-more"
                        size: Theme.px(22)
                        on: root.more
                        opacity: root.touchFirst || hover.hovered || root.more ? 1 : 0.55
                        Accessible.name: Tr.t("More actions")
                        onClicked: root.more = !root.more
                    }
                    // close: always there to a screen reader and a keyboard, clearer on hover
                    IconButton {
                        icon: "window-close"
                        size: Theme.px(22)
                        opacity: root.touchFirst || hover.hovered || root.critical ? 1 : 0.55
                        Accessible.name: Tr.t("Dismiss")
                        onClicked: root.dismissCard()
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.hideContent ? Tr.t("Notification") : (root.notification ? root.notification.summary : "")
                    textFormat: Text.PlainText
                    color: root.hideContent ? Theme.dim : Theme.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.type("heading")
                    font.weight: Font.DemiBold
                    font.italic: root.hideContent
                }
                Text {
                    Layout.fillWidth: true
                    visible: !root.hideContent && text !== ""
                    text: root.hideContent ? "" : root.safeBody(root.notification ? root.notification.body : "")
                    textFormat: Text.PlainText
                    color: Theme.dim
                    wrapMode: Text.Wrap
                    maximumLineCount: root.popup ? 3 : 6
                    elide: Text.ElideRight
                    lineHeight: 1.1
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12.5) * Theme.fontScale
                }
            }
        }

        // suggested replies (SmartReplies: Chronoa writes three), one click sends one
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
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
            id: replyField
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
            implicitHeight: Theme.px(34)
            radius: Theme.px(12)
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
                        // a critical notification (an incoming call) needs an
                        // unmissable primary action, not a soft-accent hint
                        color: pill.pressed ? Theme.pressed
                             : index === 0 && root.actions.length > 0 && root.critical ? Theme.accent
                             : pill.containsMouse ? Theme.alpha(Theme.accent, 0.22)
                             : index === 0 && root.actions.length > 0 ? Theme.accentSoft : Theme.hover
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.modelData.text
                            color: index === 0 && root.actions.length > 0 && root.critical ? Theme.accentInk
                                 : index === 0 && root.actions.length > 0 ? Theme.accent : Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.type("body")
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

    // progress reported by the app (download, copy, transfer): -1 means none.
    // Placed below the body, above the popup's time-left line.
    Rectangle {
        visible: notification && notification.progress >= 0 && notification.progress <= 1 && !hideContent
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: Theme.px(12); rightMargin: Theme.px(12); bottomMargin: 8 }
        height: Theme.px(4)
        radius: 2
        color: Theme.alpha(Theme.accent, 0.2)
        Rectangle {
            width: parent.width * notification.progress
            height: parent.height
            radius: parent.radius
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: 180 } }
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

    // long press / right click: the same small menu the desktop uses elsewhere
    Glass {
        id: contextMenu
        visible: false
        strong: true
        z: 20
        radius: Theme.px(12)
        width: Theme.px(190)
        height: menuCol.implicitHeight + 12
        Column {
            id: menuCol
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: [
                    { icon: "edit-copy", label: Tr.t("Copy text"), run: () => {
                        const n = root.notification;
                        if (n) Quickshell.clipboardText = n.summary + (n.body ? "\n" + root.safeBody(n.body) : "");
                    } },
                    { icon: "notifications-disabled", label: Tr.t("Mute app"), run: () => {
                        if (root.notification) Notifs.setSilenced(root.notification.appName, true);
                    } },
                    { icon: "preferences-system-notifications", label: Tr.t("Open app settings"), run: () => {
                        const name = root.notification ? root.notification.appName : "";
                        Ui.closeAll();
                        Ui.openSettings("notifications", "label:" + name);
                    } }
                ]
                ListRow {
                    required property var modelData
                    width: menuCol.width
                    icon: modelData.icon
                    title: modelData.label
                    onClicked: { contextMenu.visible = false; modelData.run(); }
                }
            }
        }
    }
}
