"""Uniformity of the shared Common widget set.

Static checks pin the conventions every surface can rely on (one toggle name,
one disabled look, real touch targets, one AT name for every interactive
widget). The pure checks exercise the shared JS helpers the same way the shell
does: Tools.js is a frozen catalog, Format.js has one formatter per style, and
Accents.js measures its inks instead of assuming they read.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shani/Common"


def src(name):
    return (COMMON / name).read_text(encoding="utf-8")


def first(text, pattern):
    m = re.search(pattern, text)
    assert m, pattern
    return m.group(0).strip()


def js_run(code):
    result = subprocess.run(["node", "-e", code], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout.strip())


def js_source(name):
    """Load a Common/*.js as plain JS: QML pragmas and .import are not JS."""
    text = src(name)
    text = re.sub(r"^\.pragma[^\n]*$", "", text, flags=re.M)
    return re.sub(r"^\.import[^\n]*$", "", text, flags=re.M)


def node_code(*names):
    return "var __src = " + json.dumps("\n".join(js_source(n) for n in names)) + ";\n"


NODE = pytest.mark.skipif(shutil.which("node") is None, reason="node not available")


# ---- one name for one thing -------------------------------------------------


def test_toggle_controls_all_speak_checked():
    for name in ("Button.qml", "SwitchRow.qml"):
        assert re.search(r"property bool checked\b", src(name)), name
    assert "root.on" in first(src("IconButton.qml"), r"property alias checked:[^\n]+")
    assert "root.selected" in first(src("Choice.qml"), r"property alias checked:[^\n]+")
    # old spellings stay valid: the aliases are additive
    assert "property bool on: false" in src("IconButton.qml")
    assert "property bool selected: false" in src("Choice.qml")


def test_only_one_tooltip_spelling_in_common():
    for path in COMMON.glob("*.qml"):
        assert "property string tooltip" not in path.read_text(encoding="utf-8"), path


def test_label_and_accessible_name_are_both_honoured():
    choice = src("Choice.qml")
    assert 'root.accessibleName !== "" ? root.accessibleName : root.text' in choice
    assert 'root.accessibleName !== "" ? root.accessibleName : root.tip' in src(
        "IconButton.qml"
    )
    assert "root.label || root.placeholder" in src("TextField.qml")


# ---- states -----------------------------------------------------------------


DISABLED_CUE = {
    "Button.qml": "if (!enabled) return Theme.alpha",
    "IconButton.qml": "root.enabled ? 1 : 0.45",
    "Choice.qml": "root.enabled ? 1 : 0.45",
    "SwitchRow.qml": "root.enabled ? 1 : 0.45",
}
DISABLED_GUARD = {
    "Button.qml": "if (root.enabled) root.clicked()",
    "IconButton.qml": "if (root.enabled) root.clicked()",
    "Choice.qml": "KeyFocus { enabled: root.enabled && root.visible",
    "SwitchRow.qml": "if (root.enabled) root.toggled(!root.checked)",
}


@pytest.mark.parametrize("name", sorted(DISABLED_CUE))
def test_disabled_controls_look_and_act_disabled(name):
    text = src(name)
    assert DISABLED_CUE[name] in text, name
    assert DISABLED_GUARD[name] in text, name


def test_switch_row_disables_pointer_keys_and_reset():
    text = src("SwitchRow.qml")
    assert "enabled: root.enabled\n                cursorShape: root.enabled ?" in text
    assert "KeyFocus { enabled: root.enabled && root.visible" in text
    assert 'enabled: root.enabled\n            icon: "view-refresh"' in text


def test_confirm_button_forwards_name_and_enabled_to_its_button():
    text = src("ConfirmButton.qml")
    assert "enabled: root.enabled" in text
    assert 'root.Accessible.name !== "" ? root.Accessible.name : root.text' in text
    assert re.search(r"root\.confirmed\(root\.(?:value|id)\)", text)
    assert "function disarm()" in text


def test_no_bare_empty_accessible_name_in_common():
    for path in COMMON.glob("*.qml"):
        for m in re.finditer(
            r"(?<![\w.])Accessible\.name\s*:\s*\"\"", path.read_text(encoding="utf-8")
        ):
            pytest.fail(
                f"{path.name}:{path.read_text(encoding='utf-8').count(chr(10), 0, m.start()) + 1}"
            )


# ---- sizing and a11y ---------------------------------------------------------


@pytest.mark.parametrize(
    "name",
    ["Button.qml", "IconButton.qml", "Choice.qml", "ListRow.qml", "SegmentedTabs.qml"],
)
def test_interactive_common_widgets_keep_a_touch_target(name):
    assert "Theme.touchTarget" in src(name), name
    assert "Theme.px(" in src(name), name


def test_segmented_tabs_move_the_thumb_when_at_speaks():
    text = src("SegmentedTabs.qml")
    assert "implicitHeight: Math.max(Theme.px(40), Theme.touchTarget)" in text
    assert (
        "Accessible.onPressAction: { tabs.currentIndex = segment.index; tabs.activated(segment.index) }"
        in text
    )


@pytest.mark.parametrize(
    "name",
    [
        "Button.qml",
        "IconButton.qml",
        "Choice.qml",
        "SwitchRow.qml",
        "ListRow.qml",
    ],
)
def test_interactive_common_widgets_carry_a_role_and_a_name(name):
    text = src(name)
    assert "Accessible.role:" in text, name
    assert "Accessible.name:" in text, name


def test_confirm_button_reuses_the_named_button():
    text = src("ConfirmButton.qml")
    assert "import qs.Common" in text
    assert re.search(r"^\s*Button \{", text, flags=re.M)


def test_shared_animations_honour_reduce_motion():
    for name in ("Choice.qml", "ListRow.qml", "SwitchRow.qml", "Spinner.qml"):
        text = src(name)
        assert "reduceMotion" in text or "Fade {" in text or "Theme.mot(" in text, name
    for name in ("Button.qml", "IconButton.qml", "SegmentedTabs.qml"):
        assert "Theme.mot(" in src(name) or "Theme.anim" in src(name), name


def test_busy_note_is_one_wrapping_row_not_a_contradiction():
    text = src("BusyNote.qml")
    assert "Spinner { size: root.iconSize }" in text
    assert "text: root.note" in text
    assert "wrapMode: Text.Wrap" in text
    assert "elide:" not in text  # elide is ignored when wrapping
    assert "Accessible.role: Accessible.StatusBar" in text


def test_empty_state_and_info_banner_share_token_names():
    for name in ("EmptyState.qml", "InfoBanner.qml"):
        text = src(name)
        for prop in ("iconSize", "padding", "accessibleRole"):
            assert re.search(r"property int " + prop + r"\b", text), (name, prop)


# ---- the shared catalog and formatters --------------------------------------


def test_tools_catalog_is_a_frozen_unique_nine():
    text = src("Tools.js")
    assert text.lstrip().startswith("//")
    assert "var list = [" in text
    assert "function" not in text
    entries = re.findall(
        r'\{ label: "([^"]+)", icon: "([^"]+)", flag: "([^"]+)", op: "([^"]+)",(?: settings: "[^"]+",)? words: "([^"]+)" \}',
        text,
    )
    assert len(entries) == 9
    assert len({e[2] for e in entries}) == 9
    assert len({e[3] for e in entries}) == 9
    ui = (ROOT / "shani/Common/Ui.qml").read_text(encoding="utf-8")
    for label, icon, flag, op, words in entries:
        assert op == flag + "Open", (flag, op)
        if f'flag: "{flag}", op: "{op}", settings:' not in text:   # not a Settings page
            assert f"property bool {flag}:" in ui, flag
        assert "tool" in words.split(), flag
        for part in re.findall(r"[A-Z]?[a-z]+", flag):
            assert part.lower() in words.lower(), (flag, part)
        assert icon


@NODE
def test_format_keeps_one_formatter_per_style():
    code = (
        node_code("Format.js")
        + """
    var f = new Function(__src + "; return { humanSize: humanSize, msToNextMinute: msToNextMinute, isoWeek: isoWeek, minutes: minutes };")();
    console.log(JSON.stringify({
      binary: [f.humanSize(500), f.humanSize(1536), f.humanSize(1048576), f.humanSize(1073741824)],
      si: [f.humanSize(999, "si"), f.humanSize(1000, "si"), f.humanSize(10000, "si")],
      tb: f.humanSize(1099511627776, "tb"),
      whole: f.humanSize(1048576, "whole"),
      minute: f.msToNextMinute(),
      week: f.isoWeek(new Date(2026, 0, 1)),
      time: [f.minutes("09:30"), f.minutes("bad")]
    }));
    """
    )
    out = js_run(code)
    assert out["binary"] == ["500 B", "1.5 KB", "1.0 MB", "1.0 GB"]
    assert out["si"] == ["999 B", "1.0 kB", "10 kB"]
    assert out["tb"] == "1.0 TB"
    assert out["whole"] == "1 MB"
    assert 1000 <= out["minute"] <= 60250
    assert out["week"] == 1
    assert out["time"] == [570, -1]


@NODE
def test_accents_measure_ink_contrast_for_every_slot():
    code = (
        "var __contrast = "
        + json.dumps(js_source("Contrast.js"))
        + ";\n"
        + "var __hct = "
        + json.dumps(js_source("Hct.js"))
        + ";\n"
        + "var __accents = "
        + json.dumps(js_source("Accents.js"))
        + ";\n"
        + """
    var Qt = {
      rgba: function (r, g, b, a) { return { r: r, g: g, b: b, a: a }; },
      color: function (s) {
        var h = String(s).replace("#", "");
        return Qt.rgba(parseInt(h.slice(0, 2), 16) / 255, parseInt(h.slice(2, 4), 16) / 255,
                       parseInt(h.slice(4, 6), 16) / 255, 1);
      }
    };
    var Contrast = new Function("Qt", __contrast + "; return { ratio: ratio };")(Qt);
    var Hct = new Function("Qt", __hct + "; return { toHct: toHct, fromHct: fromHct, darkerTone: darkerTone, harmonize: harmonize };")(Qt);
    var a = new Function("Qt", "Contrast", "Hct", __accents + "; return { SLOTS: SLOTS, derive: derive, derivePreset: derivePreset, accentInk: accentInk, ratio: Contrast.ratio };")(Qt, Contrast, Hct);
    var primary = Qt.color("#0986d3");
    var dark = a.derive(primary, false), light = a.derive(primary, true);
    var ratios = a.SLOTS.map(function (slot) {
      return [a.ratio(dark[slot].onContainer, dark[slot].container),
              a.ratio(light[slot].onContainer, light[slot].container)];
    });
    console.log(JSON.stringify({
      slots: a.SLOTS, dark: Object.keys(dark), light: Object.keys(light),
      worst: Math.min.apply(null, ratios.map(function (r) { return Math.min(r[0], r[1]); })),
      preset: !!a.derivePreset("CuboCore blue", false),
      ink: !!a.accentInk("CuboCore blue", false)
    }));
    """
    )
    out = js_run(code)
    assert out["slots"] == [
        "red",
        "orange",
        "yellow",
        "green",
        "teal",
        "blue",
        "purple",
        "pink",
    ]
    assert out["dark"] == out["slots"] and out["light"] == out["slots"]
    assert out["worst"] >= 4.5
    assert out["preset"] and out["ink"]
