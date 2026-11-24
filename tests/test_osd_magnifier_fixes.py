"""Static guards for OSD and Magnifier fixes.

Each check is source-only (no live compositor): i18n wrappers for user-facing
OSD labels, explicit toggle state instead of label string matching, accessible
naming, lock suppression, and magnifier bounds/accessibility/lock handling.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OSD = ROOT / "shani" / "Modules" / "Osd" / "Osd.qml"
MAG = ROOT / "shani" / "Modules" / "Magnifier" / "Magnifier.qml"


def _handler(text, name):
    """The body of one `function name(...)` up to its closing brace."""
    start = text.index("function " + name + "(")
    depth = 0
    for i in range(text.index("{", start), len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    raise AssertionError(name + " has no closing brace")


def test_osd_user_labels_are_translated():
    t = OSD.read_text(encoding="utf-8")
    # representative labels that were hardcoded; they must go through Tr.t()
    for literal in [
        'Tr.t("Ambient light sensor found")',
        'Tr.t("No ambient light sensor")',
        'Tr.t("Caps Lock on")',
        'Tr.t("Caps Lock off")',
        'Tr.t("Night light on")',
        'Tr.t("Night light off")',
        'Tr.t("Connected")',
        'Tr.t("Disconnected")',
        'Tr.t("Battery saver on")',
        'Tr.t("Flashlight on")',
        'Tr.t("Flashlight off")',
    ]:
        assert literal in t, literal
    # no raw English toggle labels left in show() calls
    for raw in [
        '"Do not disturb on"',
        '"Caffeine on"',
        '"Focus off"',
        '"Flashlight off"',
        '"Battery saver on"',
    ]:
        assert raw not in t.replace(f"Tr.t({raw})", "")


def test_osd_toggle_uses_explicit_state_not_label_matching():
    t = OSD.read_text(encoding="utf-8")
    assert "property bool toggleOn: false" in t
    show = _handler(t, "show")
    assert "toggleOn" in show
    # UI binds to toggleOn, not English label fragments
    assert "color: root.toggleOn ? Theme.accent : Theme.hover" in t
    assert "x: root.toggleOn ? parent.width - width - 2 : 2" in t
    assert 'root.label.indexOf(" on")' not in t


def test_osd_announces_state_for_assistive_tech():
    t = OSD.read_text(encoding="utf-8")
    assert "Accessible.role: Accessible.AlertMessage" in t
    assert "Accessible.name:" in t
    # slider with no label override announces percentage
    assert 'root.kind === "slider" && root.label === ""' in t


def test_osd_does_not_show_stale_state_while_locked():
    t = OSD.read_text(encoding="utf-8")
    show = _handler(t, "show")
    assert "Lock.locked" in show
    assert "if (Lock.locked) root.shown = false" in t


def test_magnifier_is_accessible_clamped_and_hidden_when_locked():
    t = MAG.read_text(encoding="utf-8")
    assert "Accessible.role: Accessible.Window" in t
    assert 'Accessible.name: Tr.t("Magnifier %1×").arg(win.zoom.toFixed(1))' in t
    # position is clamped to window bounds
    assert "function clampAt(p)" in t
    assert "win.at = win.clampAt(Qt.point(m.x, m.y))" in t
    # lock hides/closes magnifier
    assert "&& !Lock.locked" in t
    assert "if (Lock.locked) Ui.magnifier = false" in t
