pragma Singleton
// The notification daemon (org.freedesktop.Notifications) and its history.
// Every notification is kept until dismissed (the control center lists it);
// popups are a separate, short-lived view of new ones, suppressed by Do Not
// Disturb except for critical urgency.
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import qs.Common

Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values.slice().reverse()
    readonly property int count: list.length
    property var popups: []          // newest last
    readonly property bool dnd: Settings.data.doNotDisturb

    function setDnd(on) {
        Settings.data.doNotDisturb = on;
    }
    function clearAll() {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        popups = [];
    }
    function dropPopup(n) {
        popups = popups.filter(p => p !== n);
        if (n && n.transient && n.tracked)
            n.expire();
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true

        onNotification: n => {
            n.tracked = true;
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = root.popups.concat([n]).slice(-4);
            n.closed.connect(() => root.popups = root.popups.filter(p => p !== n));
        }
    }
}
