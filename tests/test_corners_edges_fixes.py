"""Regressions for the hot-corner, edge-strip and magnifier input fixes.

Static source checks (the QML is driven in a live shell, not by pytest), same
style as tests/test_form_factor_wiring.py.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _src(rel):
    return (ROOT / rel).read_text()


def test_hot_corner_hit_area_is_big_enough_to_trigger():
    src = _src("shani/Modules/HotCorners/HotCorners.qml")
    assert "implicitWidth: Theme.px(12)" in src
    assert "implicitHeight: Theme.px(12)" in src
    assert "implicitWidth: 2\n" not in src  # the old near-unhittable 2 px corner
    assert "implicitHeight: 2\n" not in src


def test_hot_corner_dwell_stops_when_the_corner_hides():
    src = _src("shani/Modules/HotCorners/HotCorners.qml")
    assert "onVisibleChanged: if (!visible) dwell.stop()" in src


def test_edge_strips_are_off_over_a_fullscreen_window():
    src = _src("shani/Modules/EdgeStrips/EdgeStrips.qml")
    assert "!(GameMode.top && GameMode.top.fullscreen)" in src


def test_magnifier_ignores_horizontal_only_wheel_events():
    src = _src("shani/Modules/Magnifier/Magnifier.qml")
    assert "if (w.angleDelta.y === 0) return;" in src
    assert "w.angleDelta.y > 0 ? 0.5 : -0.5" in src  # clamped zoom still there


def test_magnifier_has_a_keyboard_fresh_frame_and_hint():
    src = _src("shani/Modules/Magnifier/Magnifier.qml")
    assert "e.key === Qt.Key_R) win.grab();" in src
    assert "R / right-click: fresh frame" in src
