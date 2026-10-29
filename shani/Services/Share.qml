pragma Singleton
// One "Share…" for a file (after the share sheets of macOS and Windows): the
// phone (KDE Connect), a paired Bluetooth device, LocalSend (nearby devices of
// any kind — the image's AirDrop), email, or the clipboard — as the file
// itself (text/uri-list, so it pastes into Files or a chat) or its path.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string file: ""              // the file being shared, while the sheet is open
    readonly property string name: file.split("/").pop()
    property string done: ""              // what happened last, for the tests

    function open(path) { if (path) file = path; }
    function close() { file = ""; }

    readonly property var targets: file === "" ? [] : [
        ...(Phone.reachable ? [{ icon: "phone", label: "Send to " + Phone.name, run: () => Phone.send(root.file) }] : []),
        ...BtSend.devices.map(d => ({ icon: d.icon || "bluetooth-active", label: "Bluetooth: " + (d.name || d.address), run: () => { BtSend.pick(root.file); BtSend.sendTo(d); } })),
        { icon: "network-wireless", label: "Nearby devices (LocalSend)", run: () => Quickshell.execDetached(["flatpak", "run", "org.localsend.localsend_app", root.file]) },
        { icon: "mail-send", label: "Email", run: () => Quickshell.execDetached(["xdg-email", "--attach", root.file]) },
        { icon: "edit-copy", label: "Copy the file", run: () => { copyFile.command = ["sh", "-c", 'printf "file://%s\\r\\n" "$1" | wl-copy --type text/uri-list', "sh", root.file]; copyFile.running = true; } },
        { icon: "edit-copy", label: "Copy its path", run: () => Quickshell.clipboardText = root.file },
        { icon: "document-open", label: "Open with…", run: () => Quickshell.execDetached(["gio", "open", root.file]) }
    ]
    function choose(i) {
        const t = targets[i];
        if (!t)
            return;
        done = t.label;
        t.run();
        close();
    }
    Process { id: copyFile }
}
