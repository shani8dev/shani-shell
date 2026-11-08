pragma Singleton
// Phones through KDE Connect: every device it knows — paired or only nearby —
// to pair, unpair, ring, ping and send files or the clipboard to. A phone that
// asks to pair arrives as kdeconnectd's own notification, with Accept/Reject.
// The first paired, reachable one is "the phone" of the tile and the Shelf.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool available: false
    property var devices: []            // [{ id, name, paired, reachable }]
    readonly property var phone: devices.find(d => d.paired && d.reachable) || null
    readonly property string id: phone ? phone.id : ""
    readonly property string name: phone ? phone.name : ""
    readonly property bool reachable: phone !== null
    property int battery: -1

    function run(args) {
        act.command = ["kdeconnect-cli"].concat(args);
        act.running = true;
    }
    function ring(dev) { Quickshell.execDetached(["kdeconnect-cli", "-d", dev || id, "--ring"]); }
    function ping(dev) { Quickshell.execDetached(["kdeconnect-cli", "-d", dev || id, "--ping"]); }
    function send(path, dev) { Quickshell.execDetached(["kdeconnect-cli", "-d", dev || id, "--share", path]); }
    function sendClipboard(dev) { Quickshell.execDetached(["kdeconnect-cli", "-d", dev || id, "--share-text", Quickshell.clipboardText]); }
    function pair(dev) { run(["-d", dev, "--pair"]); }
    function unpair(dev) { run(["-d", dev, "--unpair"]); }
    // ask the network again (a phone that just opened the app), then list
    function search() { if (root.available) run(["--refresh"]); }
    function refresh() { if (root.available) list.running = true; }

    // Shani Link pages (shani-link-app, dev.shani.Link.App): the Phone page
    // holds the dial pad, Messages, Contacts, Music, Files and Remote. The
    // dial pad also dials the landline and the SIM modem, so these work even
    // when no KDE Connect phone is paired - Phone.available only gates the
    // phone's own ring/ping/share above. --dial prefills the pad and never
    // dials until Call is pressed; --message opens Messages addressed to the
    // number; opening the page alone lands on the Calls tab (recents first).
    function openDial(number) {
        const n = (number || "").trim();
        if (!n)
            Quickshell.execDetached(["shani-link-app", "--page", "phone"]);
        else
            Quickshell.execDetached(["shani-link-app", "--page", "phone", "--dial=" + n]);
    }
    function openMessages(number) {
        const n = (number || "").trim();
        Quickshell.execDetached(["shani-link-app", "--page", "phone", "--message=" + n]);
    }
    function openRecentCalls() {
        Quickshell.execDetached(["shani-link-app", "--page", "phone"]);
    }
    function openPhone() { openDial(""); }

    Process {
        running: true
        command: ["sh", "-c", "command -v kdeconnect-cli"]
        onExited: code => { root.available = code === 0; root.refresh(); }
    }
    Process {
        id: act
        onExited: Qt.callLater(root.refresh)
    }
    // "- Pixel 8: 1a2b3c (paired and reachable)", one per device; LC_ALL=C so
    // the state words are not translated
    Process {
        id: list
        command: ["env", "LC_ALL=C", "kdeconnect-cli", "-l"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.devices = text.split("\n").map(l => l.match(/^- (.*): (\S+) \((.*)\)$/)).filter(m => m).map(m => ({
                    id: m[2],
                    name: m[1],
                    paired: m[3].indexOf("paired") >= 0,
                    reachable: m[3].indexOf("reachable") >= 0
                }));
                if (root.reachable)
                    battery.running = true;
                else
                    root.battery = -1;
            }
        }
    }
    Process {
        id: battery
        command: ["sh", "-c", 'busctl --user get-property org.kde.kdeconnect /modules/kdeconnect/devices/"$1"/battery org.kde.kdeconnect.device.battery charge 2>/dev/null | awk "{print \\$2}"', "sh", root.id]
        stdout: StdioCollector { onStreamFinished: root.battery = parseInt(text.trim()) || -1 }
    }
    Timer { interval: 60000; running: root.available; repeat: true; onTriggered: root.refresh() }
}
