// Put in a shell surface that has no Common/KeyFocus of its own (every KeyFocus
// does this already): the surface's window is known to Ui.navAuditAll, so what in
// it takes a click but no keys is found (dev/shell-parts/pad-reach.sh).
import QtQuick
import qs.Common

Item {
    readonly property var navWindow: Window.window
    onNavWindowChanged: Ui.navSeen(navWindow)
}
