pragma Singleton
// Battery state, shared by the chrome components (Glass, Theme) that live
// in Common and so cannot import the services themselves. Services/Power
// writes this; Common reads it. onBattery deliberately does not persist.
import Quickshell
import QtQuick

Singleton {
    id: root
    property bool onBattery: false
}
