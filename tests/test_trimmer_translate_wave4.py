"""Wave 4 deep pass: explicit Video Trimmer destination and Translate copy feedback.

There is no QML runtime in this suite, so the small validation rules are mirrored
as pure Python functions and exercised on edge cases; static assertions pin the
QML hooks those behaviours depend on, so a later edit cannot silently drop them.
"""

import json
import math
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PANEL = (ROOT / "shani/Modules/VideoTrimmer/VideoTrimmerPanel.qml").read_text(
    encoding="utf-8"
)
SERVICE = (ROOT / "shani/Services/VideoTrimmer.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "shani/Modules/Translate/TranslateWindow.qml").read_text(
    encoding="utf-8"
)
TEMPLATE = json.loads((ROOT / "shani/i18n/template.json").read_text(encoding="utf-8"))


# ---- pure logic mirrors of the QML validation ------------------------------


def set_start(v, duration, end):
    """Mirror of VideoTrimmer.setStart(): clamped and strictly before end."""
    v = float(v)
    if not math.isfinite(v):
        return None
    v = max(0.0, v)
    if duration > 0:
        v = min(v, duration)
    if end > 0 and v >= end:
        v = max(0.0, end - 0.1)
    return v


def set_end(v, start, duration):
    """Mirror of VideoTrimmer.setEnd(): clamped and strictly after start."""
    v = float(v)
    if not math.isfinite(v):
        return None
    v = max(start + 0.1, v)
    if duration > 0:
        v = min(v, duration)
    return v


def can_cut(start, end, duration):
    """A cut needs a strictly ordered range inside the file (when known)."""
    if not math.isfinite(start) or not math.isfinite(end):
        return False
    if end <= start:
        return False
    return duration <= 0 or (start >= 0 and end <= duration)


def add_segment(s, e, duration):
    """Mirror of VideoTrimmer.addSegment(): rejects bad ranges, clamps to bounds."""
    s, e = float(s), float(e)
    if not math.isfinite(s) or not math.isfinite(e) or e <= s:
        return False
    if duration > 0:
        s = max(0.0, s)
        e = min(e, duration)
    return e > s


def swap(source, target):
    """Translate.swap() only flips real languages; 'auto' is not a language."""
    if source == "auto":
        return source, target
    return target, source


def language_codes():
    """Codes in TranslateWindow's pick list."""
    start = WINDOW.index("readonly property var languages:")
    block = WINDOW[start : WINDOW.index("property string result:", start)]
    return re.findall(r'\["([a-z]{2})",\s*"[^"]+"\]', block)


@pytest.mark.parametrize("value,expected", [(-5, 0.0), (20, 20.0), (100, 39.9)])
def test_start_is_clamped_and_stays_before_end(value, expected):
    assert set_start(value, 60, 40) == pytest.approx(expected)


@pytest.mark.parametrize("value,expected", [(5, 10.1), (25, 25.0), (100, 60.0)])
def test_end_is_clamped_and_stays_after_start(value, expected):
    assert set_end(value, 10, 60) == pytest.approx(expected)


@pytest.mark.parametrize("bad", [float("nan"), float("inf"), float("-inf")])
def test_non_finite_offsets_are_rejected(bad):
    assert set_start(bad, 60, 40) is None
    assert set_end(bad, 10, 60) is None


def test_cut_requires_an_ordered_in_bounds_range():
    assert can_cut(2, 5, 60)
    assert not can_cut(5, 5, 60)  # zero length
    assert not can_cut(8, 3, 60)  # backwards
    assert not can_cut(-1, 3, 60)  # before the file
    assert not can_cut(3, 61, 60)  # past the end
    assert can_cut(3, 61, 0)  # unknown duration: do not over-restrict


def test_segments_keep_the_same_range_rules():
    assert add_segment(2, 5, 60)
    assert not add_segment(5, 2, 60)
    assert not add_segment(4, 4, 60)
    assert add_segment(59, 61, 60)  # clamped to the file, not rejected
    assert add_segment(59, 61, 0)


def test_language_codes_are_real_two_letter_codes():
    codes = language_codes()
    assert len(codes) >= 12
    assert len(codes) == len(set(codes)), "duplicate language code"
    assert all(len(code) == 2 and code.isalpha() for code in codes)
    assert "en" in codes and "hi" in codes


def test_swap_flips_codes_and_ignores_auto():
    assert swap("hi", "en") == ("en", "hi")
    assert swap("auto", "en") == ("auto", "en")


# ---- static hooks -----------------------------------------------------------


def test_trimmer_has_an_explicit_save_destination():
    assert 'mode: "save"' in PANEL
    assert "FilePicker.open(" in PANEL and "defaultName:" in PANEL
    assert "win.exportPath" in PANEL and "function pickExport()" in PANEL
    assert 'Tr.t("Save as…")' in PANEL and 'Tr.t("Save trimmed copy")' in PANEL
    assert 'Accessible.name: Tr.t("Save trimmed copy")' in PANEL
    # the bridge has no output-path argument: move the finished file, keeping
    # result in sync so Open and Trash still act on the same path
    assert "function onResultChanged()" in PANEL
    assert '"mv", "-f", "--"' in PANEL and "moveProc.destination" in PANEL
    assert "VideoTrimmer.result = moveProc.destination" in PANEL


def test_trimmer_does_not_reuse_a_stale_destination():
    assert PANEL.count('win.exportPath = ""') >= 3
    assert "VideoTrimmer.cut()" in PANEL
    assert "VideoTrimmer.cutSegments()" in PANEL
    assert "VideoTrimmer.cancelCut()" in PANEL
    assert 'win.exportError = Tr.t("Could not save")' in PANEL


def test_trimmer_keeps_exact_range_progress_and_error_states():
    for hook in (
        "id: startField",
        "id: endField",
        'label: Tr.t("Start offset (seconds)")',
        'label: Tr.t("End offset (seconds)")',
        "onEditingFinished()",
        "VideoTrimmer.progress",
        "VideoTrimmer.error",
        "win.exportError",
    ):
        assert hook in PANEL, hook
    assert "end <= start" in SERVICE and 'Tr.t("End must be after start")' in SERVICE


def test_trimmer_uses_theme_tokens_not_opaque_cards():
    assert "Theme.surface1" in PANEL and "Theme.stroke" in PANEL
    assert not re.search(r"color:\s*[\"']#", PANEL)
    assert "enabled: false" not in PANEL


def test_translate_confirms_a_copy_on_screen():
    assert "property bool copied: false" in WINDOW
    assert 'text: win.copied ? Tr.t("Copied") : Tr.t("Copy")' in WINDOW
    assert "Quickshell.clipboardText = win.result; win.copied = true" in WINDOW
    assert "id: copiedTimer" in WINDOW and "copiedTimer.restart()" in WINDOW
    # abandon actions drop the stale confirmation with the stale answer
    assert "win.copied = false;" in WINDOW


def test_translate_keeps_swap_clear_and_keyboard_routes():
    assert "function swap()" in WINDOW and "win.swap()" in WINDOW
    assert "exchange-positions" in WINDOW
    assert 'onClicked: { win.cancel(); input.text = ""; }' in WINDOW
    assert "Ctrl+Enter translates" in WINDOW
    assert "Accessible.role: Accessible.EditableText" in WINDOW
    assert "Accessible.role: Accessible.StaticText" in WINDOW


@pytest.mark.parametrize("path", [PANEL, WINDOW])
def test_new_strings_are_registered_in_the_catalog(path):
    for literal in re.findall(r'Tr\.t\(\s*("(?:[^"\\]|\\.)*")', path):
        key = json.loads(literal)
        assert key in TEMPLATE, f"unregistered string: {key}"
