pragma Singleton
// The one place colours, type and shape live. Modules bind to these tokens and
// never write a literal colour, so the greeter and lock screen share them too.
//
// Two palettes, following the Dark style switch (the same one apps follow), and
// an accent that is either ShaniOS amber (the Saturn brand orange) or — with
// "accent from wallpaper" — the picture's most vivid colour, lightened or
// darkened until it reads on the current palette. Text on the accent picks
// black or white by its lightness.
import Quickshell
import QtQuick

Singleton {
    id: root
    // Use a property binding instead of readonly to ensure reactivity
    // when Settings.data.darkMode changes via IPC or file sync
    property bool dark: Settings.data.darkMode

    // ---- the accent ---------------------------------------------------------
    readonly property color brand: "#ff7f50"
    ColorQuantizer {
        id: quant
        source: Settings.data.accentFromWallpaper && root.wallpaper ? ("file://" + String(root.wallpaper).replace(/ /g, "%20")) : ""
        depth: 3                        // 8 candidates
        rescaleSize: 96
    }
    // the most saturated candidate, at a lightness that reads on this palette.
    // A wallpaper is mostly sky, rock and shadow: those near-greys are not an
    // accent, so candidates below a real accent's saturation are skipped and
    // the chosen accent is used instead of a washed-out slate. The winner keeps
    // the picture's hue but is pushed to an accent's vividness — lightening it
    // to "read on dark" is what turned a teal wall into pale grey-blue.
    readonly property color picked: {
        const cs = quant.colors || [];
        let best = null, score = -1;
        for (const c of cs) {
            if (c.hslSaturation < 0.22 || c.hslLightness < 0.08 || c.hslLightness > 0.92)
                continue;
            const s = c.hslSaturation * (1 - Math.abs(c.hslLightness - 0.5));
            if (s > score) { score = s; best = c; }
        }
        if (!best)
            return root.chosen;
        return Qt.hsla(best.hslHue, Math.max(0.55, best.hslSaturation), dark ? 0.62 : 0.38, 1);
    }
    // GNOME's nine accents, a light and a dark tone each (libadwaita's values);
    // orange tuned to ShaniOS's brand on dark (the Saturn metadata accent)
    readonly property var accents: ({
        blue: ["#3584e4", "#78aeed"], teal: ["#1f8f7c", "#7fd1c1"], green: ["#3a944a", "#8ff0a4"],
        yellow: ["#c88800", "#f8e45c"],
        orange: ["#bc3e18", "#ff7f50"],   // the brand amber: deep on light, Saturn coral on dark
        red: ["#e01b24", "#f66151"],
        pink: ["#d56199", "#f49ac1"], purple: ["#9141ac", "#dc8add"], slate: ["#6f8396", "#9aa8b8"]
    })
    readonly property color chosen: (accents[Settings.data.accentName] || accents.orange)[dark ? 1 : 0]
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
    // Adaptive palette (matugen): when on and a palette is loaded, the Material
    // roles override the tonal material on the four core tokens. The whole
    // shell follows, since every surface binds to these.
    function _mat(role, fallback) {
        return Settings.data.adaptivePalette && Matugen.ready && Matugen.palette[role]
            ? Matugen.palette[role] : fallback;
    }
    readonly property color bg: contrast ? (dark ? "#000000" : "#ffffff") : (dark ? _mat("surface", tone(0.22, 0.065)) : _mat("surface", tone(0.28, 0.945)))
    readonly property color text: contrast ? (dark ? "#ffffff" : "#000000") : (dark ? _mat("on_surface", tone(0.20, 0.93)) : _mat("on_surface", tone(0.35, 0.11)))
    readonly property color dim: contrast ? (dark ? "#e0e6ee" : "#1a1a1a") : (dark ? _mat("on_surface_variant", tone(0.14, 0.66)) : _mat("on_surface_variant", tone(0.14, 0.37)))
    readonly property color faint: contrast ? (dark ? "#b8c2cf" : "#333333") : (dark ? _mat("outline", tone(0.10, 0.44)) : _mat("outline", tone(0.10, 0.58)))
    readonly property color border: contrast ? stroke : _mat("outline_variant", stroke)   // adaptive variant where a mid outline is wanted
    // adaptive base: the colour every translucent layer is cut from. Without
    // the adaptive palette this is the tonal material above, and the ladder
    // below is byte-for-byte what it always was; with it, matugen's surface
    // takes the base and each step keeps its lightness delta and its alpha —
    // so blur density and layering read exactly as designed.
    function _shade(c, ds, dl, a) {
        const col = Qt.color(c);
        return Qt.hsla(col.hslHue,
                       Math.min(1, Math.max(0, col.hslSaturation + ds)),
                       Math.min(1, Math.max(0, col.hslLightness + dl)), a);
    }
    readonly property color _base: _mat("surface",
        dark ? tone(0.22, 0.065) : tone(0.28, 0.945))
    readonly property color amber: dark ? "#e0af68" : "#b7791f"
    readonly property color blue: dark ? "#7aa2f7" : "#3461c1"
    readonly property color red: dark ? "#f7768e" : "#c8364f"
    readonly property color danger: dark ? "#f28b82" : "#c0392b"

    // glass: the translucent card every surface is drawn on
    // with blur the glass is thinner - what is behind shows, softened; without
    // it, denser, so text stays readable over whatever is there
    readonly property bool blurred: Settings.blurWanted && !Settings.data.reduceTransparency
    readonly property color glass: contrast ? bg : (dark ? _shade(_base, 0.04, 0.010, blurred ? 0.58 : 0.66) : _shade(_base, 0.07, 0.030, blurred ? 0.68 : 0.72))
    readonly property color glassStrong: contrast ? bg : (dark ? _shade(_base, 0.04, 0.010, blurred ? 0.74 : 0.88) : _shade(_base, 0.07, 0.030, blurred ? 0.82 : 0.93))
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
    readonly property color card: contrast ? bg : (dark ? _shade(_base, 0.02, 0.035, 0.62) : _shade(_base, 0.02, 0.045, 0.82))
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

    readonly property int radius: Settings.data.cornerRadius !== undefined ? Settings.data.cornerRadius : 16
    readonly property int radiusSmall: Settings.data.cornerRadiusSmall !== undefined ? Settings.data.cornerRadiusSmall : 10
    readonly property int radiusLarge: Math.max(radius + 6, 22)
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
    readonly property color surface1: contrast ? bg : (dark ? _shade(_base, 0.02, 0.055, 0.70) : _shade(_base, 0.02, 0.045, 0.75))
    readonly property color surface2: contrast ? bg : (dark ? _shade(_base, 0.02, 0.090, 0.78) : _shade(_base, 0.02, 0.020, 0.85))
    readonly property color surface3: contrast ? bg : (dark ? _shade(_base, 0.02, 0.125, 0.86) : _shade(_base, 0.02, -0.010, 0.92))

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
}
