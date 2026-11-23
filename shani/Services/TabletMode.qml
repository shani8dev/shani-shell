pragma Singleton
// A convertible folded into a tablet, and a laptop's lid: niri's own switch events
// (switch-events in the shell's shani-input.kdl, Services/InputConfig) call the
// shell's IPC `switchEvent` - niri reads the kernel's switches through libinput, so
// no reader of our own runs. Entering tablet mode shows the screen keyboard,
// leaving hides it (Settings > Keyboard & input, on by default); the keyboard's
// floating button follows it too. `lidClosed` is the lid, as niri saw it last.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    property bool known: false            // a switch said something
    property bool on: false
    property bool lidClosed: false
    property bool oskFromTablet: false   // the OSK we raised by folding: only we may close it
    onOnChanged: {
        if (!known || !Settings.data.oskWithTabletMode)
            return;
        if (on !== Osk.shown) {
            Osk.toggle();
            root.oskFromTablet = on && Osk.shown;
        }
    }
    Connections {
        target: Settings.data
        // switching the feature off mid-fold used to leave our keyboard up for good
        function onOskWithTabletModeChanged() {
            if (!Settings.data.oskWithTabletMode && root.oskFromTablet && Osk.shown) {
                Osk.toggle();
                root.oskFromTablet = false;
            }
        }
    }
    Connections {
        target: Osk
        // a keyboard closed by its own rules is no longer ours to close on unfold
        function onShownChanged() { if (!Osk.shown) root.oskFromTablet = false; }
    }
    function event(what) {
        if (what === "tablet-on" || what === "tablet-off") {
            root.known = true;
            root.on = what === "tablet-on";
        } else if (what === "lid-close" || what === "lid-open")
            root.lidClosed = what === "lid-close";
    }
}
