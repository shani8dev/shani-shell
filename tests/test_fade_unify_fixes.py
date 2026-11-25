"""Static checks: the shared Fade component and its adopted sites.

One reusable accent-pulse (Common/Fade.qml) replaces the hand-rolled
"SequentialAnimation on opacity" rings/glows. These tests pin the component
contract, each adopted site, and the reduce-motion guarantee.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shani/Common"
FADE = (COMMON / "Fade.qml").read_text()
LISTROW = (COMMON / "ListRow.qml").read_text()
ISLAND = (ROOT / "shani/Modules/Island/Island.qml").read_text()


def test_fade_component_contract():
    # a Rectangle wrapper exposing the documented surface
    assert "Rectangle {" in FADE
    assert "property int duration: Theme.anim * 4" in FADE
    assert "property var easing: Easing.InOutSine" in FADE
    assert "property real pulseFrom: 0.35" in FADE
    assert "property real pulseTo: 1.0" in FADE
    assert "property bool active: false" in FADE
    assert "function flash()" in FADE


def test_fade_flash_settles_and_honours_reduce_motion():
    # one-shot flash is a no-op under reduce motion; the loop never runs there
    assert "if (!Settings.data.reduceMotion) once.restart();" in FADE
    assert "running: root.active && !Settings.data.reduceMotion" in FADE
    assert "loops: Animation.Infinite" in FADE


def test_listrow_uses_fade_for_flash_ring():
    # the hand-rolled SequentialAnimation on opacity is gone, replaced by Fade
    assert "Fade {" in LISTROW
    assert "id: flashRing" in LISTROW
    assert "active: root.highlighted" in LISTROW
    assert "duration: Theme.mot(420)" in LISTROW
    assert "SequentialAnimation on opacity" not in LISTROW


def test_island_uses_fade_for_breath_glow():
    assert "Fade {" in ISLAND
    assert "id: breathGlow" in ISLAND
    assert 'active: win.working && Chronoa.state !== "offline"' in ISLAND
    assert "duration: Theme.mot(1100)" in ISLAND
    assert "pulseTo: 0.85" in ISLAND
    # the old per-site pulse animation is gone
    assert 'property: "opacity"; from: 0.35; to: 0.85' not in ISLAND
