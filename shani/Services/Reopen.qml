pragma Singleton
// Reopen your apps at the next sign-in (macOS's "Reopen windows when logging
// back in", Windows' "restart apps"): the apps open now are written down as
// they change, and the first time the shell starts in a new login session they
// are offered back - by a notification, or straight away (Settings > Default
// apps > Startup). A restart of the shell is not a sign-in: the login session
// (boot id + XDG_SESSION_ID) is written with the list. Only apps with a
// desktop entry are kept: that is what starts them again.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string session: ""
    property var offered: []             // desktop ids offered back at this sign-in
    property bool decided: false         // the last session's list was read and dealt with
    readonly property string mode: Settings.data.reopenApps   // "ask" | "always" | "never"
    readonly property var openNow: {
        const out = [];
        for (const w of Object.values(Niri.windows)) {
            if (!w.app_id || w.app_id === "org.quickshell")
                continue;
            const e = DesktopEntries.byId(w.app_id) || DesktopEntries.heuristicLookup(w.app_id);
            if (e && !e.noDisplay && out.indexOf(e.id) < 0)
                out.push(e.id);
        }
        return out;
    }
    property var saved: []               // what the file says now (the tests read it)

    function reopen(ids) {
        for (const id of ids) {
            const e = DesktopEntries.byId(id);
            if (e) e.execute();
        }
    }
    function offer(ids) {
        offered = ids;
        if (!ids.length || mode === "never")
            return;
        if (mode === "always") {
            reopen(ids);
            return;
        }
        const names = ids.map(id => { const e = DesktopEntries.byId(id); return e ? e.name : id; });
        ask.command = ["notify-send", "-a", "Shani", "-i", "view-restore", "-A", "reopen=" + Tr.t("Reopen"),
                       Tr.t("Reopen your apps?"), names.join(", ")];
        ask.running = true;
    }
    function decide(previous) {
        if (decided)
            return;
        decided = true;
        if (previous && previous.session !== session)
            offer((previous.apps || []).filter(id => DesktopEntries.byId(id)));
        save.restart();
    }

    Process {
        id: ask
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "reopen") root.reopen(root.offered) }
    }
    Process {
        running: true
        command: ["sh", "-c", 'printf "%s:%s" "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" "${XDG_SESSION_ID:-}"']
        stdout: StdioCollector {
            onStreamFinished: { root.session = text.trim(); file.reload(); }
        }
    }
    FileView {
        id: file
        path: root.session ? Quickshell.statePath("open-apps.json") : ""
        printErrors: false
        onLoaded: {
            let d = null;
            try { d = JSON.parse(text()); } catch (e) {}
            root.saved = d ? d.apps || [] : [];
            // the windows of a running session are not all known at once
            Qt.callLater(() => root.decide(d));
        }
        onLoadFailed: root.decide(null)
    }
    onOpenNowChanged: if (decided) save.restart()
    // not on every change: as a session ends its apps close one by one, and
    // the shell is gone before this fires, so the list kept is the last calm one
    Timer {
        id: save
        interval: 5000
        onTriggered: {
            root.saved = root.openNow;
            file.setText(JSON.stringify({ session: root.session, apps: root.openNow }));
        }
    }
}
