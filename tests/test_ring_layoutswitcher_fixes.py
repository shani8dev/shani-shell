"""Static checks for Ring/LayoutSwitcher gaps found by reading Ring.qml and
LayoutSwitcher.qml, not listed in docs/GAPS.md or docs/GAPS-RESEARCH.md.

These modules are QML shell surfaces, so tests assert the source carries the
wiring rather than driving a live compositor.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ring = (ROOT / "shani/Modules/Ring/Ring.qml").read_text(encoding="utf-8")
layout = (ROOT / "shani/Modules/LayoutSwitcher/LayoutSwitcher.qml").read_text(
    encoding="utf-8"
)


def test_ring_keyboard_navigation_moves_and_activates_hot_slice():
    assert "function moveHot(step)" in ring
    assert "hot = hot < 0 ? (step > 0 ? 0 : items.length - 1)" in ring
    assert "(hot + step + items.length) % items.length" in ring
    assert "e.key === Qt.Key_Left || e.key === Qt.Key_Up" in ring
    assert "e.key === Qt.Key_Right || e.key === Qt.Key_Down" in ring
    assert (
        "e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space"
        in ring
    )
    assert "if (win.hot >= 0)" in ring
    assert "win.choose(win.hot);" in ring


def test_ring_exposes_accessible_dialog_and_slice_actions():
    assert "Accessible.role: Accessible.Dialog" in ring
    assert 'Accessible.name: Tr.t("Ring menu")' in ring
    assert "Accessible.role: Accessible.Button" in ring
    assert 'Accessible.name: (modelData.label || "")' in ring
    assert 'modelData.children ? ", " + Tr.t("submenu") : ""' in ring
    assert "Accessible.focused: isHot" in ring
    assert "Accessible.onPressAction: win.choose(index)" in ring


def test_ring_filters_empty_child_groups_and_clamps_stale_hot():
    assert "].filter(it => it.act || (it.children && it.children.length > 0));" in ring
    assert "onItemsChanged: if (hot >= items.length) hot = -1" in ring


def test_layout_switcher_enter_applies_and_keeps_like_button():
    assert (
        'Shortcut { sequences: ["Return", "Enter"]; enabled: root.visible; onActivated: { if (!root.tried) root.tryOn(root.sel); root.keep(); } }'
        in layout
    )


def test_layout_switcher_preview_minis_are_ignored_by_accessibility():
    mini = layout.split("component Mini: Rectangle {", 1)[1].split(
        "readonly property real u: width / 160", 1
    )[0]
    assert "Accessible.ignored: true" in mini
