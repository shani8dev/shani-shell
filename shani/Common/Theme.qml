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
    // One material, tinted by the accent's hue (from the wallpaper, or chosen):
    // the background, the glass, the text all lean the same way at low
    // saturation, so the bar, panels and pop-ups read as one surface - not grey
    // panels with a coloured highlight. Grey accents (no hue) fall back to slate.
    readonly property real hue: accent.hslHue >= 0 ? accent.hslHue : 0.6
    function tone(sat, light, a) { return Qt.hsla(hue, sat, light, a === undefined ? 1 : a); }
    readonly property color bg: contrast ? (dark ? "#000000" : "#ffffff") : (dark ? tone(0.22, 0.065) : tone(0.28, 0.945))
    readonly property color text: contrast ? (dark ? "#ffffff" : "#000000") : (dark ? tone(0.20, 0.93) : tone(0.35, 0.11))
    readonly property color dim: contrast ? (dark ? "#e0e6ee" : "#1a1a1a") : (dark ? tone(0.14, 0.66) : tone(0.14, 0.37))
    readonly property color faint: contrast ? (dark ? "#b8c2cf" : "#333333") : (dark ? tone(0.10, 0.44) : tone(0.10, 0.58))
    readonly property color amber: dark ? "#e0af68" : "#b7791f"
    readonly property color blue: dark ? "#7aa2f7" : "#3461c1"
    readonly property color red: dark ? "#f7768e" : "#c8364f"
    readonly property color danger: dark ? "#f28b82" : "#c0392b"

    // glass: the translucent card every surface is drawn on
    // with blur the glass is thinner - what is behind shows, softened; without
    // it, denser, so text stays readable over whatever is there
    readonly property bool blurred: Settings.data.blur && !Settings.data.reduceTransparency
    readonly property color glass: contrast ? bg : (dark ? tone(0.26, 0.075, blurred ? 0.58 : 0.66) : tone(0.35, 0.975, blurred ? 0.68 : 0.72))
    readonly property color glassStrong: contrast ? bg : (dark ? tone(0.26, 0.075, blurred ? 0.74 : 0.88) : tone(0.35, 0.975, blurred ? 0.82 : 0.93))
    readonly property color stroke: contrast ? alpha(text, 0.85) : (dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09))
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color accentSoft: alpha(accent, dark ? 0.18 : 0.16)
    readonly property color accentLine: alpha(accent, 0.55)
    // accent on interactive state: a little stronger on hover, full on press
    readonly property color accentHover: alpha(accent, dark ? 0.30 : 0.22)
    readonly property color accentPressed: alpha(accent, dark ? 0.45 : 0.35)
    readonly property color scrim: dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0.05, 0.08, 0.12, 0.22)
    // elevation shadows: soft, card, raised — depth without drawing borders on everything
    readonly property color shadowSoft: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color shadowCard: dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.18)
    readonly property color shadowRaised: dark ? Qt.rgba(0, 0, 0, 0.70) : Qt.rgba(0, 0, 0, 0.28)
    readonly property color shadow: shadowCard   // default, backward-compatible

    // card: a solid surface that floats on glass — for tiles, chips, buttons
    readonly property color card: contrast ? bg : (dark ? tone(0.24, 0.10, 0.62) : tone(0.30, 0.99, 0.82))
    readonly property color cardBorder: contrast ? alpha(text, 0.5) : (dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))

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
    // Motion (Material 3's "emphasized"): a panel arrives over a longer time
    // on a strongly decelerating curve and leaves quickly - the polish of a
    // drawer, not a pop. All 0 with reduce motion.
    readonly property int animEnter: Settings.data.reduceMotion ? 0 : 420
    readonly property int animExit: Settings.data.reduceMotion ? 0 : 200
    readonly property var emphasized: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]           // decelerate: arriving
    readonly property var emphasizedExit: [0.3, 0.0, 0.8, 0.15, 1.0, 1.0]       // accelerate: leaving

    // Surface ladder: raised tones of the same hue for what sits on a panel
    // (tiles, cards, fields), each step a little nearer the light - depth
    // without borders or shadows on everything.
    readonly property color surface1: contrast ? bg : (dark ? tone(0.24, 0.12, 0.70) : tone(0.30, 0.99, 0.75))
    readonly property color surface2: contrast ? bg : (dark ? tone(0.24, 0.155, 0.78) : tone(0.30, 0.965, 0.85))
    readonly property color surface3: contrast ? bg : (dark ? tone(0.24, 0.19, 0.86) : tone(0.30, 0.935, 0.92))

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
}
