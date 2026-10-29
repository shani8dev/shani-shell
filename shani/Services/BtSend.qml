pragma Singleton
// Sending a file to a Bluetooth device (a phone's "receive via Bluetooth"):
// obexd's own client — CreateSession(opp) → ObjectPush1.SendFile → watch the
// transfer's Status → RemoveSession — through gdbus. The device must be paired.
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property string file: ""              // waiting for a device to be picked
    property bool busy: send.running
    readonly property var devices: Bluetooth.devices.values.filter(d => d.paired)

    function pick(path) { file = path; }
    function sendTo(device) {
        if (!file || send.running)
            return;
        send.command = ["sh", "-c", 'addr="$1"; f="$2"; o=org.bluez.obex
            s=$(gdbus call --session --dest $o --object-path /org/bluez/obex --method $o.Client1.CreateSession "$addr" "{\\"Target\\": <\\"opp\\">}" 2>&1) || { echo "$s" >&2; exit 1; }
            s=$(echo "$s" | grep -o "/org/bluez/obex/client/[a-z0-9/]*" | head -1)
            t=$(gdbus call --session --dest $o --object-path "$s" --method $o.ObjectPush1.SendFile "$f" 2>&1 | grep -o "/org/bluez/obex/client/[a-z0-9/]*" | head -1)
            st=queued; i=0
            while [ -n "$t" ] && [ $i -lt 600 ]; do
                st=$(gdbus call --session --dest $o --object-path "$t" --method org.freedesktop.DBus.Properties.Get $o.Transfer1 Status 2>/dev/null | grep -o "complete\\|error\\|active\\|queued\\|suspended" | head -1)
                [ "$st" = complete ] || [ "$st" = error ] || [ -z "$st" ] && break; sleep 0.5; i=$((i + 1)); done
            gdbus call --session --dest $o --object-path /org/bluez/obex --method $o.Client1.RemoveSession "$s" >/dev/null 2>&1
            # a transfer object that is gone has finished
            [ "$st" = complete ] || [ -z "$st" ]', "sh", device.address, file];
        target = device.name || device.address;
        send.running = true;
    }
    property string target: ""
    Process {
        id: send
        stderr: StdioCollector { id: err }
        onExited: code => {
            Quickshell.execDetached(["notify-send", "-a", "Bluetooth", "-i", "bluetooth-active",
                code === 0 ? "Sent to " + root.target : "Could not send to " + root.target,
                root.file.split("/").pop() + (code === 0 ? "" : " — is it paired, on and accepting files?")]);
            root.file = "";
        }
    }
}
