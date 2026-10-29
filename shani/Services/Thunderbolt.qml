pragma Singleton
// Thunderbolt devices waiting to be allowed (bolt): a dock, a drive, an eGPU
// plugged in stays unauthorized until someone says yes. The shell asks — as a
// notification with Allow once / Always allow — through bolt's own D-Bus API
// (gdbus): Device1.Authorize, or Manager1.EnrollDevice to remember it.
// bolt's polkit rules decide whether a password is asked.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string bolt: "org.freedesktop.bolt"
    property var asked: ({})               // device path → true, so each is asked once per plug

    // a device: if it is connected but not authorized, ask
    function consider(path) {
        if (asked[path])
            return;
        askComp.createObject(root, { path: path });
    }
    // the ones already waiting at start, then each one that arrives
    Process {
        running: true
        command: ["sh", "-c", 'gdbus call --system --dest org.freedesktop.bolt --object-path /org/freedesktop/bolt --method org.freedesktop.bolt1.Manager.ListDevices 2>/dev/null | grep -o "/org/freedesktop/bolt/devices/[A-Za-z0-9_]*"']
        stdout: SplitParser { onRead: line => root.consider(line.trim()) }
    }
    Process {
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.bolt", "--object-path", "/org/freedesktop/bolt"]
        stdout: SplitParser {
            onRead: line => {
                const m = /DeviceAdded \(objectpath '([^']+)'/.exec(line);
                if (m)
                    root.consider(m[1]);
            }
        }
    }
    Component {
        id: askComp
        Process {
            id: ask
            property string path
            running: true
            // its name and status, then — if it waits — the question
            command: ["sh", "-c", 'p="$1"; g() { gdbus call --system --dest org.freedesktop.bolt --object-path "$p" --method org.freedesktop.DBus.Properties.Get org.freedesktop.bolt1.Device "$1" 2>/dev/null | sed -n "s/^(<.\\(.*\\).>,)$/\\1/p"; }
                [ "$(g Status)" = connected ] || exit 0
                name="$(g Vendor) $(g Name)"; uid=$(g Uid)
                a=$(notify-send -a Thunderbolt -i thunderbolt -u critical -A once="Allow once" -A always="Always allow" -A no="Not now" "Allow this Thunderbolt device?" "$name — once allowed, it can read and write memory directly")
                case "$a" in
                once) gdbus call --system --dest org.freedesktop.bolt --object-path "$p" --method org.freedesktop.bolt1.Device.Authorize "" >/dev/null ;;
                always) gdbus call --system --dest org.freedesktop.bolt --object-path /org/freedesktop/bolt --method org.freedesktop.bolt1.Manager.EnrollDevice "$uid" "default" "" >/dev/null ;;
                esac', "sh", path]
            onExited: { root.asked[ask.path] = true; ask.destroy(); }
        }
    }
}
