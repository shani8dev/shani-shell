"""Static checks for QML patterns that have hung or broken the shell.

- A child of a Flow/Row/Grid bound to `width: parent.width`: the positioner's
  size comes from its children and the child's from the positioner, so it
  re-lays itself out every frame (2026-11-04: Settings > Network froze the
  shell after Personalisation had widened the page).
- A Repeater directly under a Scope/ShellRoot making windows: a Repeater makes
  its items only under a visual parent, so the windows are never created
  (hot corners, 2026-10-29) - Variants is the one for that.
"""
import re
from pathlib import Path

SHANI = Path(__file__).parent.parent / "shani"
POSITIONERS = {"Flow", "Row", "Grid", "Column"}


def blocks(text):
    """(line number, line, enclosing type names) for every line."""
    stack = []
    for n, line in enumerate(text.split("\n"), 1):
        yield n, line, [t for t, _ in stack]
        m = re.match(r"\s*([A-Z]\w*) \{\s*$", line)
        if m:
            stack.append((m.group(1), len(line) - len(line.lstrip())))
        elif line.strip() == "}" and stack:
            stack.pop()


def test_no_child_sized_to_its_positioner():
    bad = []
    for f in SHANI.rglob("*.qml"):
        for n, line, enclosing in blocks(f.read_text()):
            one_line_child = re.match(r"\s*[A-Z]\w* \{.*\bwidth: parent\.width\b", line)
            if one_line_child and enclosing and enclosing[-1] in POSITIONERS:
                bad.append(f"{f.relative_to(SHANI)}:{n} ({enclosing[-1]})")
    assert not bad, "a child sized to its own positioner (it re-lays out forever): " + ", ".join(bad)


def test_windows_are_made_by_variants_not_repeaters():
    bad = []
    for f in SHANI.rglob("*.qml"):
        t = f.read_text()
        for m in re.finditer(r"Repeater \{[^{}]*?(delegate: )?(PanelWindow|FloatingWindow|PopupWindow) \{", t):
            bad.append(f"{f.relative_to(SHANI)}:{t[:m.start()].count(chr(10)) + 1}")
    assert not bad, "a Repeater making windows (only Variants makes them outside a visual parent): " + ", ".join(bad)


def test_toggle_roles_answer_the_toggle_action():
    """A radio button, check box or switch is activated by AT-SPI's *Toggle*
    action (action 0 for those roles), not Press: a control with that role and
    only `onPressAction` can't be chosen by a screen reader at all. Measured
    2026-11-04: every Choice chip, the layout tiles and the accent swatches.
    A display-only indicator (no action handler of any kind) is fine."""
    import re
    bad = []
    for path in sorted(SHANI.rglob("*.qml")):
        lines = path.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            if not re.search(r"Accessible\.role:\s*Accessible\.(RadioButton|CheckBox|Switch)\b", line):
                continue
            # the object's own Accessible block: this line and the next few
            block = "\n".join(lines[i:i + 8])
            if "onPressAction" in block and "onToggleAction" not in block:
                bad.append(f"{path.relative_to(SHANI)}:{i + 1}")
    assert not bad, "toggle-role controls that only answer Press (a screen reader can't choose them): " + ", ".join(bad)
