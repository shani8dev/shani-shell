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


def test_no_property_takes_a_built_in_items_name():
    """`property int left` on an Item is "Cannot override FINAL property": the
    whole file fails to load (the Authenticator never opened). The names every
    Item already has (its edges, size, place, look) are not for declaring."""
    import re
    from pathlib import Path
    # the ones Qt makes FINAL on every Item (a service, which is no Item, may use the others)
    builtin = {"left", "right", "top", "bottom", "horizontalCenter", "verticalCenter", "baseline", "x", "y", "z",
               "width", "height", "parent", "children", "anchors"}
    root = Path(__file__).resolve().parent.parent / "shani"
    wrong = []
    for path in root.rglob("*.qml"):
        text = path.read_text()
        top = re.search(r"^([A-Z]\w*)\s*\{", text, re.M)
        # a service (a Singleton, a QtObject, a Scope) is no Item: its own `x` or `top` is fine
        if "pragma Singleton" in text or (top and top.group(1) in ("Singleton", "QtObject", "Scope", "Variants")):
            continue
        # a window's own properties are not an Item's (a PanelWindow's `top` is fine); the items inside it are
        window = bool(top and (top.group(1).endswith("Window") or top.group(1) == "ShellRoot"))
        for n, line in enumerate(text.splitlines(), 1):
            m = re.match(r"(\s*)(?:readonly\s+|required\s+|default\s+)*property\s+[\w<>.]+\s+(\w+)\b", line)
            if m and window and len(m.group(1)) <= 4:
                continue
            m = m and re.match(r"\s*(?:readonly\s+|required\s+|default\s+)*property\s+[\w<>.]+\s+(\w+)\b", line)
            if m and m.group(1) in builtin:
                wrong.append(f"{path.relative_to(root)}:{n}: {m.group(1)}")
    assert wrong == []


def test_no_password_or_secret_is_made_with_math_random():
    """Math.random is not a source of secrets (it is predictable): the
    Passwords app made passwords with it until 2026-11-12. A file that makes a
    password, a PIN, a token or a key takes them from the system (`secrets`)."""
    import re
    from pathlib import Path
    root = Path(__file__).resolve().parent.parent / "shani"
    wrong = []
    for path in root.rglob("*.qml"):
        code = re.sub(r"//[^\n]*", "", path.read_text())
        if "Math.random" in code and re.search(r"password|passphrase|\bpin\b|token|secret", code, re.I):
            wrong.append(path.name)
    assert wrong == []
