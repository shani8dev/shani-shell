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
    property int seq: 0                   // monotonic counter: a unique path per render
    readonly property bool shown: image !== ""

    function show(title, text) {
        if (!text)
            return;
        root.title = title;
        root.text = text;
        root.seq++;
        // unique per render so two consecutive shares never overwrite each
        // other (a viewer left open used to show the newer code)
        const out = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shani-qr-" + root.seq + "-" + Date.now() + ".png";
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

    // Save the current PNG to a destination the person chose via FilePicker
    // (argv slots, no shell). Silent when there is nothing rendered yet.
    function saveTo(path) {
        if (!path || !image)
            return;
        saveProc.command = ["cp", "-f", image, path];
        saveProc.running = true;
    }
    Process {
        id: saveProc
        onExited: code => {
            Quickshell.execDetached(["notify-send", "-a", "QR code",
                code === 0 ? Tr.t("QR code saved") : Tr.t("Could not save QR code")]);
        }
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
