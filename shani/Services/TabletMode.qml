pragma Singleton
// A convertible folded into a tablet: the kernel's SW_TABLET_MODE switch, read
// from the switch device's evdev node by bridge/tablet-mode.py (blocking reads:
// it wakes only when the switch moves). Entering tablet mode shows the screen
// keyboard, leaving hides it (Settings > Keyboard & input, on by default); the
// keyboard's floating button follows it too. Only runs on a computer whose udev
// database has such a switch (InputKinds.tabletSwitch).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_TABLET_MODE_TOOL") || "/usr/lib/shani-shell/tablet-mode.py"
    property bool known: false            // a switch said something
    property bool on: false
    onOnChanged: {
        if (!known || !Settings.data.oskWithTabletMode)
            return;
        if (on !== Osk.shown)
            Osk.toggle();
    }
    Process {
        running: InputKinds.tabletSwitch
        command: ["python3", root.tool]
        stdout: SplitParser {
            onRead: line => {
                if (line === "tablet" || line === "laptop") {
                    root.known = true;
                    root.on = line === "tablet";
                }
            }
        }
    }
}
