pragma Singleton
// Dynamic lock (after Windows): a paired phone (or watch) chosen in Settings >
// Privacy; when it leaves Bluetooth range and stays gone for 30 seconds, the
// screen locks. The grace keeps a Bluetooth hiccup from locking anyone out.
import Quickshell
import Quickshell.Bluetooth
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string address: Settings.data.dynamicLockDevice
    readonly property var device: address ? Bluetooth.devices.values.find(d => d.address === address) || null : null
    readonly property bool present: device !== null && device.connected
    property bool wasPresent: false
    property int locks: 0                 // for the tests

    onPresentChanged: {
        if (present) {
            wasPresent = true;
            grace.stop();
        } else if (wasPresent && address)
            grace.restart();
    }
    // the tests stand in for a phone walking away
    function away() { if (address) { wasPresent = true; grace.restart(); } }
    Timer {
        id: grace
        interval: Quickshell.env("SHANI_DYNAMIC_LOCK_GRACE") ? parseInt(Quickshell.env("SHANI_DYNAMIC_LOCK_GRACE")) : 30000
        onTriggered: {
            if (root.present || Lock.locked)
                return;
            root.locks++;
            Lock.lock();
        }
    }
}
