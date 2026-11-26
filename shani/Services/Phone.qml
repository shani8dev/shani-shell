pragma Singleton
// The shell's Android phone: the handset AndroidTools can reach over cable or
// Wi-Fi debugging. Pairing happens in Devices with Bluetooth or the code the
// phone shows; nothing is installed on the phone. Ring and ping need an app on
// the handset, so the shell does not offer them.
import Quickshell
import qs.Common

Singleton {
    id: root

    // One answer from the native tools, kept as a map so a newer answer never
    // mixes with an older one. An empty map means the tools have not answered.
    readonly property var phoneState: AndroidTools.result.state || ({})

    // Tools that answered can connect a phone; a paired phone may still be away.
    readonly property bool available: AndroidTools.result.state !== undefined
    readonly property bool reachable: !!phoneState.paired
    readonly property string name: reachable ? String(phoneState.name || "") : ""

    // "76%, charging" -> 76 for the tile; the row keeps the charging flag too.
    readonly property int battery: {
        const match = /^(\d+)%/.exec(String(phoneState.battery || ""));
        return match ? parseInt(match[1], 10) : -1;
    }

    readonly property string serial: reachable ? String(phoneState.serial || "") : ""
    readonly property var devices: reachable ? [{
        id: root.serial,
        name: root.name,
        paired: true,
        reachable: true,
        battery: root.battery,
        charging: /charging/i.test(String(phoneState.battery || ""))
    }] : []

    function search() { AndroidTools.refresh(); AndroidTools.run("find", []); }
    function refresh() { AndroidTools.refresh(); }
    // The copy goes to the phone that is connected now; a device name cannot
    // make the native tools pick a different one.
    function send(path, dev) { AndroidTools.run("copy", [path]); }

    // A device from the link service carries its battery as a number and its
    // charging flag beside it; render both, or show nothing when there is no
    // battery reading.
    function batteryText(dev) {
        if (!dev || typeof dev.battery !== "number" || dev.battery < 0)
            return "";
        return Math.max(0, Math.min(100, dev.battery)) + "%"
            + (dev.charging ? " · " + Tr.t("charging") : "");
    }

    // Phone actions land in the shell's own apps: the Calls dial pad (which
    // also dials the landline and the SIM modem with no phone connected), the
    // Messages composer and the Contacts address book. A number only fills the
    // pad or the composer; nothing is dialled or sent until the person presses
    // Call or Send.
    function openDial(number) {
        // a tel:/callto: link's number (tel:+91-98200%2012345;ext=1 -> +91-98200 12345)
        Ui.callsNumber = decodeURIComponent(String(number || "").trim().replace(/^(tel|callto):(\/\/)?/i, "").split(";")[0]);
        Ui.calls = true;
    }
    function openMessages(number) {
        Ui.messagesNumber = (number || "").trim();
        Ui.messages = true;
    }
    function openContacts() { Ui.contacts = true; }
    function openRecentCalls() { Ui.calls = true; }
    function openPhone() { openDial(""); }
}
