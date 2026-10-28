pragma Singleton
// The one place colours, type and shape live. Modules bind to these tokens and
// never write a literal colour, so the greeter and lock screen share them too.
import Quickshell
import QtQuick

Singleton {
    readonly property color bg: "#0b0d12"
    readonly property color accent: "#7fd1c1"
    readonly property color text: "#e8eef5"
    readonly property color dim: "#8fa1b6"
    readonly property color faint: "#5b6878"
    readonly property color amber: "#e0af68"
    readonly property color blue: "#7aa2f7"
    readonly property color red: "#f7768e"
    readonly property color danger: "#f28b82"
    readonly property color accentInk: "#08110f"

    // glass: the translucent card every surface is drawn on
    readonly property color glass: Qt.rgba(0.05, 0.07, 0.10, 0.62)
    readonly property color glassStrong: Qt.rgba(0.05, 0.07, 0.10, 0.84)
    readonly property color stroke: Qt.rgba(1, 1, 1, 0.10)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.06)
    readonly property color pressed: Qt.rgba(1, 1, 1, 0.10)
    readonly property color accentSoft: Qt.rgba(0.50, 0.82, 0.76, 0.18)
    readonly property color accentLine: Qt.rgba(0.50, 0.82, 0.76, 0.55)
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.35)

    readonly property string font: "Noto Sans"
    readonly property string mono: "DejaVu Sans Mono"
    readonly property int fontSmall: 11
    readonly property int fontBody: 13
    readonly property int fontTitle: 15

    readonly property int radius: 16
    readonly property int radiusSmall: 10
    readonly property int radiusLarge: 22
    readonly property int gap: 12
    readonly property int barHeight: 40
    // 0 with reduce motion: every Behavior keyed on it jumps instead of moving
    readonly property int anim: Settings.data.reduceMotion ? 0 : 160

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
}
