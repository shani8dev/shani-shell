pragma Singleton
// The one place colours, type and shape live. Modules bind to these tokens and
// never write a literal colour, so the greeter and lock screen share them too.
//
// Two palettes, following the Dark style switch (the same one apps follow), and
// an accent that is either ShaniOS teal or — with "accent from wallpaper" — the
// wallpaper's most vivid colour, lightened or darkened until it reads on the
// current palette. Text on the accent picks black or white by its lightness.
import Quickshell
import QtQuick

Singleton {
    id: root
    readonly property bool dark: Settings.data.darkMode

    // ---- the accent ---------------------------------------------------------
    readonly property color brand: "#7fd1c1"
    ColorQuantizer {
        id: quant
        source: Settings.data.accentFromWallpaper && root.wallpaper ? "file://" + root.wallpaper : ""
        depth: 3                        // 8 candidates
        rescaleSize: 96
    }
    // the most saturated candidate, at a lightness that reads on this palette
    readonly property color picked: {
        const cs = quant.colors || [];
        let best = null, score = -1;
        for (const c of cs) {
            const s = c.hslSaturation * (1 - Math.abs(c.hslLightness - 0.5));
            if (s > score) { score = s; best = c; }
        }
        if (!best || best.hslSaturation < 0.15)
            return root.chosen;
        return Qt.hsla(best.hslHue, Math.max(0.45, best.hslSaturation), dark ? 0.68 : 0.40, 1);
    }
    // GNOME's nine accents, a light and a dark tone each (libadwaita's own values,
    // teal brightened to ShaniOS's brand on dark)
    readonly property var accents: ({
        blue: ["#3584e4", "#78aeed"], teal: ["#1f8f7c", "#7fd1c1"], green: ["#3a944a", "#8ff0a4"],
        yellow: ["#c88800", "#f8e45c"], orange: ["#e66100", "#ffa348"], red: ["#e01b24", "#f66151"],
        pink: ["#d56199", "#f49ac1"], purple: ["#9141ac", "#dc8add"], slate: ["#6f8396", "#9aa8b8"]
    })
    readonly property color chosen: (accents[Settings.data.accentName] || accents.teal)[dark ? 1 : 0]
    readonly property color accent: Settings.data.accentFromWallpaper ? picked : chosen
    readonly property color accentInk: accent.hslLightness > 0.55 ? "#08110f" : "#ffffff"

    // the wallpaper in use: the style's own when one is set, the one wallpaper otherwise
    readonly property string wallpaper: (dark ? Settings.data.wallpaperDark : Settings.data.wallpaperLight) || Settings.data.wallpaper

    // ---- the palette ---------------------------------------------------------
    // high contrast: opaque surfaces, strong strokes, secondary text nearly as
    // strong as text — for low vision and bright rooms
    readonly property bool contrast: Settings.data.highContrast
    readonly property color bg: dark ? (contrast ? "#000000" : "#0b0d12") : (contrast ? "#ffffff" : "#eef1f4")
    readonly property color text: dark ? (contrast ? "#ffffff" : "#e8eef5") : (contrast ? "#000000" : "#16202b")
    readonly property color dim: dark ? (contrast ? "#e0e6ee" : "#8fa1b6") : (contrast ? "#1a1a1a" : "#55657a")
    readonly property color faint: dark ? (contrast ? "#b8c2cf" : "#5b6878") : (contrast ? "#333333" : "#8b97a6")
    readonly property color amber: dark ? "#e0af68" : "#b7791f"
    readonly property color blue: dark ? "#7aa2f7" : "#3461c1"
    readonly property color red: dark ? "#f7768e" : "#c8364f"
    readonly property color danger: dark ? "#f28b82" : "#c0392b"

    // glass: the translucent card every surface is drawn on
    readonly property color glass: contrast ? bg : (dark ? Qt.rgba(0.05, 0.07, 0.10, 0.62) : Qt.rgba(0.98, 0.99, 1.0, 0.70))
    readonly property color glassStrong: contrast ? bg : (dark ? Qt.rgba(0.05, 0.07, 0.10, 0.86) : Qt.rgba(0.98, 0.99, 1.0, 0.92))
    readonly property color stroke: contrast ? alpha(text, 0.85) : (dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09))
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color accentSoft: alpha(accent, dark ? 0.18 : 0.16)
    readonly property color accentLine: alpha(accent, 0.55)
    readonly property color scrim: dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0.05, 0.08, 0.12, 0.22)
    readonly property color shadow: dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0.05, 0.1, 0.18, 0.22)

    // ---- type and shape --------------------------------------------------------
    // Inter where installed (shani-shell depends on it), the system sans otherwise
    readonly property string font: Settings.data.uiFont || "Inter"
    readonly property string mono: Settings.data.monoFont || "JetBrains Mono"
    // large text: every size in the shell is multiplied by this
    readonly property real fontScale: Settings.data.largeText ? 1.25 : 1.0
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
