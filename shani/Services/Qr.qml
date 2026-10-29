pragma Singleton
// QR codes (qrencode): text for a phone's camera — the Wi-Fi this computer is
// on (its name and password, the standard WIFI: form phones join from), or
// what is on the clipboard. Shown by QrView until closed.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    property string title: ""
    property string text: ""
    property string image: ""             // the PNG, while shown
    property int rev: 0
    readonly property bool shown: image !== ""

    function show(title, text) {
        if (!text)
            return;
        root.title = title;
        root.text = text;
        const out = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-qr.png";
        make.command = ["qrencode", "-o", out, "-s", "10", "-m", "2", "--", text];
        make.out = out;
        make.running = true;
    }
    function close() { image = ""; }
    Process {
        id: make
        property string out
        onExited: code => { if (code === 0) { root.rev++; root.image = make.out; } }
    }

    // the Wi-Fi in use, as phones read it: WIFI:T:WPA;S:<name>;P:<password>;;
    // (nmcli shows the password of a connection this person may use)
    function shareWifi() { wifi.running = true; }
    function esc(s) { return s.replace(/([\\\;,:"])/g, "\\\\$1"); }
    Process {
        id: wifi
        command: ["nmcli", "-t", "-f", "SSID,SECURITY,PASSWORD", "device", "wifi", "show-password"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                text.split("\n").forEach(l => { const i = l.indexOf(":"); if (i > 0) kv[l.slice(0, i).trim().toUpperCase()] = l.slice(i + 1).trim(); });
                if (!kv.SSID)
                    return;
                const open = !kv.PASSWORD || /none|--/i.test(kv.SECURITY || "");
                root.show("Join " + kv.SSID, "WIFI:T:" + (open ? "nopass" : /WEP/.test(kv.SECURITY) ? "WEP" : "WPA") + ";S:" + root.esc(kv.SSID)
                          + (open ? "" : ";P:" + root.esc(kv.PASSWORD)) + ";;");
            }
        }
    }
}
