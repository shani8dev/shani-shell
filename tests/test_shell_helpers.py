"""The shell's shared helpers (Common/*.js), run in node.

Contrast.js (WCAG), Shape.js (the corner scale), WheelInput.js (a wheel
against a touchpad), Hct.js + Tonal.js + Accents.js (Material's colour
space) are plain logic, so they are tested the way Fuzzy.js is: loaded into
node and asked what they answer.

They are QML libraries, so their `.import "X.js" as X` lines are turned into
plain namespaces here, and a small `Qt` stands in for the two colour calls
QML makes.
"""
import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shani" / "Common"

CONTRAST = COMMON / "Contrast.js"
SHAPE = COMMON / "Shape.js"
WHEEL = COMMON / "WheelInput.js"
HCT = COMMON / "Hct.js"
TONAL = COMMON / "Tonal.js"
ACCENTS = COMMON / "Accents.js"

node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")

# the two colour calls QML makes, and the scroll phase a wheel does not have
QT_SHIM = """
var Qt = {
    rgba: function (r, g, b, a) { return { r: r, g: g, b: b, a: a === undefined ? 1 : a }; },
    color: function (c) {
        if (typeof c === "string") {
            var h = c.replace("#", "");
            if (h.length === 3)
                h = h.split("").map(function (x) { return x + x; }).join("");
            var v = parseInt(h, 16);
            return { r: ((v >> 16) & 255) / 255, g: ((v >> 8) & 255) / 255, b: (v & 255) / 255, a: 1 };
        }
        return { r: c.r, g: c.g, b: c.b, a: c.a === undefined ? 1 : c.a };
    },
    NoScrollPhase: 0
};
"""


def read(p):
    return Path(p).read_text(encoding="utf-8")


def modules(mods):
    """A node program that has each library as a namespace, in dependency order."""
    out = [QT_SHIM]
    for namespace, path in mods:
        src = read(path).replace(".pragma library", "")
        src = re.sub(r'^\.import\s+"[^"]+"\s+as\s+\w+\s*$', "", src, flags=re.M)
        names = re.findall(r"^function\s+(\w+)\s*\(", src, flags=re.M)
        if not names:
            raise AssertionError(f"no functions found in {path}")
        out.append("var %s = (function () {\n%s\nreturn { %s };\n})();"
                   % (namespace, src, ", ".join("%s: %s" % (n, n) for n in names)))
    return "\n".join(out)


def run(mods, body):
    """Run some code with the libraries in scope; it answers with JSON."""
    prog = modules(mods) + "\n" + body
    r = subprocess.run([node, "-e", prog], capture_output=True, text=True)
    if r.returncode != 0:
        raise AssertionError(r.stderr.strip() or "node failed")
    return json.loads(r.stdout)


# ---- contrast (WCAG) ---------------------------------------------------------------

CONTRAST_MODS = [("Contrast", CONTRAST)]


def test_the_luminance_of_black_and_white_is_the_extremes():
    out = run(CONTRAST_MODS, """
    var black = { r: 0, g: 0, b: 0 };
    var white = { r: 1, g: 1, b: 1 };
    process.stdout.write(JSON.stringify({
        black: Contrast.relativeLuminance(black),
        white: Contrast.relativeLuminance(white),
        ratio: Contrast.ratio(black, white)
    }));""")
    assert out["black"] == 0
    assert abs(out["white"] - 1.0) < 1e-9
    assert abs(out["ratio"] - 21.0) < 1e-6


def test_the_ink_that_reads_on_a_background_is_chosen_by_measurement():
    # a pale colour takes dark text, a deep one takes white - and the switch
    # happens where the ratio says, not where the eye expects it
    out = run(CONTRAST_MODS, """
    var dark = { r: 0.03, g: 0.07, b: 0.06 };
    var light = { r: 1, g: 1, b: 1 };
    var onDark = Contrast.readableOn(dark, [light, dark], 4.5);
    var onLight = Contrast.readableOn(light, [light, dark], 4.5);
    process.stdout.write(JSON.stringify({
        onDark: onDark, onLight: onLight,
        darkRatio: Contrast.ratio(onDark, dark),
        lightRatio: Contrast.ratio(onLight, light)
    }));""")
    assert [out["onDark"][k] for k in "rgb"] == [1, 1, 1]
    assert [out["onLight"][k] for k in "rgb"] == [0.03, 0.07, 0.06]
    assert out["darkRatio"] >= 4.5
    assert out["lightRatio"] >= 4.5


def test_a_tint_never_goes_far_enough_to_hide_the_text():
    out = run(CONTRAST_MODS, """
    var base = { r: 0.95, g: 0.95, b: 0.95 };
    var tint = { r: 0.2, g: 0.3, b: 0.8 };
    var on = { r: 0.05, g: 0.05, b: 0.05 };
    var tinted = Contrast.subtleTint(base, tint, on, 0.5, 4.5);
    process.stdout.write(JSON.stringify({ ratio: Contrast.ratio(tinted, on) }));""")
    assert out["ratio"] >= 4.5


# ---- the corner scale ----------------------------------------------------------------

SHAPE_MODS = [("Shape", SHAPE)]


def test_the_corner_scale_carries_the_shells_own_radii():
    out = run(SHAPE_MODS, """
    process.stdout.write(JSON.stringify({
        small: Shape.radius("s", 1),
        card: Shape.radius("l", 1),
        large: Shape.radius("xl", 1),
        scaled: Shape.radius("l", 2),
        fixed: Shape.radius("l", 1, 7),
        pill: Shape.fullRadius(40, 40, 1),
        halfPill: Shape.fullRadius(40, 20, 1)
    }));""")
    assert out["small"] == 10
    assert out["card"] == 16
    assert out["large"] == 22
    assert out["scaled"] == 32
    assert out["fixed"] == 7
    assert out["pill"] == 20
    assert out["halfPill"] == 10


def test_a_roundness_strength_scales_the_whole_scale():
    out = run(SHAPE_MODS, """
    process.stdout.write(JSON.stringify({
        half: Shape.scaleForStrength(50),
        full: Shape.scaleForStrength(100),
        none: Shape.scaleForStrength(0),
        odd: Shape.scaleForStrength(150),
        fromRadius: Shape.strengthFromRadius(16)
    }));""")
    assert out["half"] == 1
    assert out["full"] == 2
    assert out["none"] == 0
    assert out["odd"] == 2          # clamped to 0..100, so 150 is 100
    assert out["fromRadius"] == 67  # 16 is two thirds of the m token


# ---- a wheel against a touchpad ----------------------------------------------------------

WHEEL_MODS = [("WheelInput", WHEEL)]


def test_a_wheel_is_a_notch_and_a_finger_is_pixels():
    # a wheel sends angles (120 a notch); a finger sends pixels
    out = run(WHEEL_MODS, """
    var wheel = { phase: 0, pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 0, y: 120 }, modifiers: 0 };
    var finger = { phase: 2, pixelDelta: { x: 0, y: 40 }, angleDelta: { x: 0, y: 10 }, modifiers: 0 };
    var smooth = { phase: 0, pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 0, y: 30 }, modifiers: 0 };
    process.stdout.write(JSON.stringify({
        wheelKind: WheelInput.verticalKind(wheel),
        fingerKind: WheelInput.verticalKind(finger),
        smoothKind: WheelInput.verticalKind(smooth),
        wheelStep: WheelInput.stepDelta(wheel, 0.05, 40),
        fingerStep: WheelInput.stepDelta(finger, 0.05, 40),
        smoothStep: WheelInput.stepDelta(smooth, 0.05, 40),
        horizontal: WheelInput.isHorizontal({ phase: 0, pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 120, y: 0 }, modifiers: 0 })
    }));""")
    assert out["wheelKind"] == "wheel"
    assert out["fingerKind"] == "touchpad"
    assert out["smoothKind"] == "highResWheel"
    assert abs(out["wheelStep"] - 0.05) < 1e-9        # one notch, one step
    assert abs(out["fingerStep"] - 0.05) < 1e-9        # forty pixels, one step
    assert out["smoothStep"] < 0.05                   # a fraction of a notch
    assert out["horizontal"] is True


def test_a_flick_never_jumps_more_than_one_step():
    out = run(WHEEL_MODS, """
    var flick = { phase: 2, pixelDelta: { x: 0, y: 4000 }, angleDelta: { x: 0, y: 0 }, modifiers: 0 };
    var manyNotches = { phase: 0, pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 0, y: 1200 }, modifiers: 0 };
    process.stdout.write(JSON.stringify({
        flick: WheelInput.stepDelta(flick, 0.05, 40),
        many: WheelInput.stepDelta(manyNotches, 0.05, 40)
    }));""")
    assert out["flick"] == 0.05
    assert out["many"] == 0.05


# ---- HCT, the tonal containers and the accents ----------------------------------------------

HCT_MODS = [("Contrast", CONTRAST), ("Hct", HCT)]
ACCENT_MODS = HCT_MODS + [("Tonal", TONAL), ("Accents", ACCENTS)]


def test_a_colour_survives_the_round_trip_through_hct():
    out = run(HCT_MODS, """
    var c = { r: 0.4, g: 0.5, b: 0.9 };
    var key = Hct.toHct(c);
    var back = Hct.fromHct(key.hue, key.chroma, key.tone);
    process.stdout.write(JSON.stringify({
        hue: key.hue, chroma: key.chroma, tone: key.tone,
        r: back.r, g: back.g, b: back.b
    }));""")
    assert abs(out["r"] - 0.4) < 0.01
    assert abs(out["g"] - 0.5) < 0.01
    assert abs(out["b"] - 0.9) < 0.01
    assert 0 <= out["tone"] <= 100


def test_the_tone_that_reads_on_a_background_is_found():
    # a darker tone reads on a light background and the other way round
    out = run(HCT_MODS, """
    var dark = Hct.darkerTone(80, 4.5);
    var light = Hct.lighterTone(20, 4.5);
    process.stdout.write(JSON.stringify({ dark: dark, light: light }));""")
    assert out["dark"] < 80
    assert out["light"] > 20


def test_every_derived_accent_has_an_ink_that_reads_on_it():
    out = run(ACCENT_MODS, """
    var primary = { r: 1, g: 0.5, b: 0.31 };
    var slots = Accents.derive(primary, false, {});
    var names = Object.keys(slots);
    var worst = 0;
    for (const name of names) {
        const s = slots[name];
        worst = Math.max(worst, 0);   // the ratio is computed below
    }
    process.stdout.write(JSON.stringify({
        names: names,
        ratios: names.map(function (n) { return Contrast.ratio(slots[n].onContainer, slots[n].container); })
    }));""")
    assert set(out["names"]) == {"red", "orange", "yellow", "green", "teal", "blue", "purple", "pink"}
    # every slot's ink reads on its container (4.5:1 is the target)
    for ratio in out["ratios"]:
        assert ratio >= 4.5, out["ratios"]


def test_a_container_is_tinted_toward_the_accent_not_toward_grey():
    out = run(ACCENT_MODS, """
    var accent = { r: 1, g: 0.5, b: 0.31 };
    var card = { r: 0.12, g: 0.12, b: 0.13 };
    var tinted = Tonal.softContainer(accent, card, 0.5);
    var plain = { r: 0.12, g: 0.12, b: 0.13 };
    process.stdout.write(JSON.stringify({
        tinted: tinted, plain: plain,
        tint: Tonal.defaultTint(card)
    }));""")
    # the tinted container keeps the card's lightness but moves toward the
    # accent's hue: its red channel rises above the plain card's
    assert out["tinted"]["r"] > out["plain"]["r"] + 0.001
    assert out["tint"] == 0.5          # a dark card takes the dark tint


# ---- the shell really uses them -----------------------------------------------------------

def test_the_shell_uses_the_shared_helpers():
    theme = read(COMMON / "Theme.qml")
    assert 'import "Contrast.js" as Contrast' in theme
    assert 'import "Shape.js" as Shape' in theme
    assert "Contrast.readableOn(root.accent" in theme       # the accent's ink is measured
    assert "Shape.radius(" in theme                         # the corners come from the scale

    color = read(ROOT / "shani" / "Services" / "Color.qml")
    assert 'import "../Common/Contrast.js" as Contrast' in color
    assert "Contrast.relativeLuminance" in color
    assert "function lin(channel)" not in color              # the copy is gone

    slider = read(COMMON / "SliderRow.qml")
    assert 'import "WheelInput.js" as WheelInput' in slider
    assert "WheelInput.stepDelta" in slider

    disktree = read(ROOT / "shani" / "Services" / "DiskUsage.qml")
    assert "Proc.run(" in disktree                           # a scan that hangs gives up
