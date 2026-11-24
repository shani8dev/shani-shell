// New notifications, top right under the bar, newest at the top. Each leaves
// after its timeout (the app's, else 6 s; critical ones stay until handled) or
// with the time left paused while hovered. They stay in the sidebar's history.
// Several from one app fold into a single stack: a header names the app and
// counts them; opening it shows the cards inside (Android / GNOME-style).
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    visible: Notifs.popups.length > 0 && !Ui.controlCenter && !Ui.launcher && !Lock.locked
        && Lens.phase !== "selecting" && Lens.phase !== "reading"   // not what Lens is pointed at
    // where pop-ups appear (Settings > Notifications); the dock keeps the bottom clear
    readonly property string pos: Settings.data.popupPosition
    anchors { top: pos !== "bottom-right"; bottom: pos === "bottom-right"; right: pos !== "top-center" }
    // clear of the bar, wherever it is: at the top it pushes a popup down; at
    // the bottom (a board) the top is free and a "bottom" popup sits above it
    readonly property bool bottomBar: FormFactor.barEdge(win.screen.name) === "bottom"
    readonly property bool atBottom: pos === "bottom-right"
    margins {
        top: bottomBar ? 12 : Theme.barHeight + 18
        right: 12
        bottom: atBottom ? (bottomBar ? Theme.barHeight + 18 : (Settings.data.dock && Settings.data.dockVisibility !== "hide" ? Settings.data.dockIconSize + 44 : 16)) : 16
    }
    // a phone's card is the width of the screen, less a margin: 380 leaves
    // 437 with the UI scale, which does not fit 412 (docs/FORM-FACTORS.md)
    readonly property bool narrow: FormFactor.focused.profile === "phone"
    implicitWidth: narrow ? win.screen.width - 24 : Theme.px(380)
    implicitHeight: list.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted ? popRegion : null
    // rounded like the cards: a plain rectangle blurred a square box behind them
    Region { id: popRegion; item: list; radius: Theme.radiusLarge }

    // one expanded stack per app key; a card on its own shows as before
    property var expanded: ({})

    // The key is the one Notifs.qml:30 builds for Notifs.perApp: the desktop
    // entry when the app gave one, else its name, lowercased. Grouping by it
    // keeps a stack together even when an app sends both kinds of notification.
    function appKey(n) {
        const key = String((n && n.desktopEntry) || (n && n.appName) || "").toLowerCase();
        return key || "other";
    }
    function groupPopups() {
        const out = [], byKey = {}, byName = {};
        for (const n of Notifs.popups.slice().reverse()) {   // newest first
            // a critical one (an incoming call) is never folded into a stack:
            // its red edge and Urgent label must be seen, not counted
            const critical = n && n.urgency === NotificationUrgency.Critical;
            const key = critical ? "critical:" + n.id : win.appKey(n);
            const name = String((n && n.appName) || "").toLowerCase();
            const desktop = String((n && n.desktopEntry) || "").toLowerCase();
            let g = byKey[key];
            // one app can send a desktop id on one notice and only its name on
            // the next. Notifs.perApp indexes both, so do the same here instead
            // of showing two stacks for the same app.
            if (!g && !critical)
                g = (name && byName[name]) || (desktop && byName[desktop]);
            if (g) {
                byKey[key] = g;
            } else {
                g = { key: key, name: n.appName || Tr.t("Notification"),
                      icon: n.appIcon || "", desktopEntry: n.desktopEntry || "", items: [] };
                out.push(g);
                byKey[key] = g;
            }
            if (!critical) {
                if (name) byName[name] = g;
                if (desktop) byName[desktop] = g;
            }
            g.items.push(n);
        }
        // a stack whose last notification expired must not linger, open or not
        return out.filter(g => g.items.length > 0);
    }
    // every popup at once: critical ones (incoming calls) stay - they never
    // leave by themselves and must be handled on their own card, not swept away
    function clearPopups() {
        for (const n of Notifs.popups.slice())
            if (n && n.urgency !== NotificationUrgency.Critical)
                n.dismiss();
        win.expanded = ({});
    }
    function toggleGroup(key) {
        const e = Object.assign({}, win.expanded);
        e[key] = !e[key];
        win.expanded = e;
    }
    // Clear all of an app's stacked popups in one press. A critical notice is
    // never in a stack (it has its own key), but never sweep one away by mistake.
    function dismissGroup(g) {
        if (!g)
            return;
        for (const n of g.items.slice())
            if (n && n.urgency !== NotificationUrgency.Critical)
                n.dismiss();
        const e = Object.assign({}, win.expanded);
        delete e[g.key];
        win.expanded = e;
    }

    // a popup card, shared by a lone notification and one inside an open stack
    component PopupCard: NotificationCard {
        id: pc
        required property var modelData
        property bool inGroup: false
        Layout.fillWidth: true
        notification: modelData
        popup: true
        showApp: !pc.inGroup              // the stack's header already names the app
        onDone: Notifs.dropPopup(modelData)
        HoverHandler { id: hover }
        // the time left runs down, paused while the pointer rests on it or the
        // card is in use (menu, reply, finger, swipe); a hidden surface (the
        // control centre, lock, launcher) pauses it rather than letting the
        // popup expire unseen
        NumberAnimation on life {
            running: win.visible && !pc.critical
            paused: running && (hover.hovered || pc.interacting)
            from: 1
            to: 0
            duration: pc.modelData.expireTimeout > 0 ? pc.modelData.expireTimeout * 1000 : Settings.data.popupSeconds * 1000
            onFinished: Notifs.dropPopup(pc.modelData)
        }
    }

    ColumnLayout {
        id: list
        width: parent.width
        spacing: Theme.px(8)
        // two or more waiting: one press clears them all, including the critical
        // ones that never leave on their own
        Glass {
            visible: Notifs.popups.length > 1
            Layout.fillWidth: true
            implicitHeight: clearRow.implicitHeight + Theme.px(6)
            radius: Theme.radiusLarge
            RowLayout {
                id: clearRow
                anchors.fill: parent
                anchors.leftMargin: Theme.px(12)
                anchors.rightMargin: Theme.px(4)
                spacing: Theme.px(6)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("%1 notifications", Notifs.popups.length)
                    color: Theme.dim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                IconButton {
                    icon: "edit-clear-all"
                    size: Theme.px(22)
                    Accessible.name: Tr.t("Clear all")
                    onClicked: win.clearPopups()
                }
            }
        }
        Repeater {
            model: win.groupPopups()
            delegate: ColumnLayout {
                id: stack
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.px(4)
                readonly property bool multi: stack.modelData.items.length > 1
                readonly property bool open: !!win.expanded[stack.modelData.key]
                readonly property string stackName: Tr.t("%1 notifications from %2", stack.modelData.items.length, stack.modelData.name)
                // the icon of the newest card in the stack
                readonly property string stackIcon: {
                    const n = stack.modelData.items[0];
                    if (!n)
                        return "";
                    if (n.appIcon)
                        return n.appIcon.startsWith("/") || n.appIcon.indexOf("://") > 0 ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
                    const e = stack.modelData.desktopEntry ? DesktopEntries.byId(stack.modelData.desktopEntry) : null;
                    return e && e.icon ? Quickshell.iconPath(e.icon, true) : "";
                }

                Glass {
                    visible: stack.multi
                    Layout.fillWidth: true
                    implicitHeight: stackHead.implicitHeight + Theme.px(10)
                    radius: Theme.radiusLarge
                    // under the row: the dismiss button on top must get its own clicks
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.toggleGroup(stack.modelData.key)
                    }
                    RowLayout {
                        id: stackHead
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(12)
                        anchors.rightMargin: Theme.px(12)
                        spacing: Theme.px(8)
                        IconImage {
                            implicitSize: Theme.px(22)
                            source: stack.stackIcon
                            visible: source !== ""
                        }
                        Text {
                            Layout.fillWidth: true
                            text: stack.modelData.name
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.px(13) * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Rectangle {
                            implicitWidth: Math.max(Theme.px(20), countText.implicitWidth + Theme.px(10))
                            implicitHeight: Theme.px(20)
                            radius: Theme.px(10)
                            color: Theme.accentSoft
                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: stack.modelData.items.length
                                color: Theme.accent
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            text: stack.open ? "▾" : "▸"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(14) * Theme.fontScale
                        }
                        IconButton {
                            icon: "window-close"
                            size: Theme.px(18)
                            accessibleName: Tr.t("Dismiss %1 notifications from %2", stack.modelData.items.length, stack.modelData.name)
                            onClicked: win.dismissGroup(stack.modelData)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: stack.stackName
                    Accessible.onPressAction: win.toggleGroup(stack.modelData.key)
                    KeyFocus {
                        name: stack.stackName
                        radius: Theme.radiusLarge
                        onActivated: win.toggleGroup(stack.modelData.key)
                    }
                }
                Repeater {
                    // a lone card shows directly; a stack shows its cards once opened
                    model: stack.multi ? (stack.open ? stack.modelData.items : []) : stack.modelData.items
                    delegate: PopupCard { inGroup: stack.multi }
                }
            }
        }
    }
}
