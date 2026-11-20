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


def test_removing_an_account_with_its_files_needs_its_name_typed():
    """Settings > Users: "Remove with their files" deletes a home folder with no
    undo, so it is enabled only when the account's exact name is typed (Ananta
    OS's rule for destructive actions), and the field empties whenever the
    confirm row opens or closes. "Remove, keep their files" stays one tap."""
    t = (SHANI / "Modules/Settings/SettingsUsers.qml").read_text()
    with_files = t[t.index('text: Tr.t("Remove with their files")'):]
    with_files = with_files[:with_files.index("}")]
    assert "enabled: typedName.text.trim() === urow.modelData.name" in with_files
    keep = t[t.index('text: Tr.t("Remove, keep their files")'):]
    keep = keep[:keep.index("}")]
    assert "enabled:" not in keep
    assert 'onConfirmChanged: typedName.text = ""' in t
    assert "visible: removeRow.visible && removeRow.confirm" in t


def test_no_process_is_named_after_its_own_methods():
    """A Process whose id is `write` (or another of its methods) hides that
    method from its own handlers: `onStarted: write(payload)` then calls the
    object, a TypeError, and the request never reaches the helper. Settings >
    Power had it from the start - lid, power button and charge limit changes
    never got to shani-admin.py (found 2026-11-19 by shell-parts/wake-sources)."""
    bad = []
    for p in SHANI.rglob("*.qml"):
        t = p.read_text()
        for m in re.finditer(r"\bProcess\s*\{\s*(?://[^\n]*\n\s*)*id:\s*(write|exec|signal|startDetached)\b", t):
            bad.append(f"{p.relative_to(SHANI)}: id {m.group(1)}")
    assert not bad, bad


def test_files_tiles_and_rows_drag_and_folders_take_drops():
    """Files: the grid's tiles, the list's rows and the other pane's tiles are each a
    real drag source (Drag.Automatic, text/uri-list - other apps take it) moved by
    their MouseArea; folders, the folder's background, the sidebar's places and the
    other pane take drops (FileDropArea). The drop's work is held by
    dev/shell-parts/files-dnd.sh; the gesture needs a pointer the suite cannot have."""
    t = (SHANI / "Modules/Files/FilesPanel.qml").read_text()
    for owner, area in (("cell", "cellArea"), ("row", "rowArea"), ("scell", "scellArea")):
        drag = t[t.index(f"id: {owner}Drag"):]
        drag = drag[:drag.index("}")]
        assert "Drag.dragType: Drag.Automatic" in drag and '"text/uri-list"' in drag, owner
        assert f"Drag.active: {area}.drag.active" in drag, owner
        assert f"drag.target: {owner}Drag" in t, owner
    assert t.count("FileDropArea {") >= 6
    d = (SHANI / "Modules/Files/FileDropArea.qml").read_text()
    assert 'keys: ["text/uri-list"]' in d and "Files.dropUrls(dest, drop.urls" in d


def test_files_right_click_opens_the_menu():
    """Files had no mouse menu at all - only the Menu key - though FEATURES says
    "the right-click menu" (found 2026-11-19). Tiles, rows and the other pane's
    tiles take the right button and open it; the background has its own (new
    folder, templates, paste, terminal, select all, turn the selection over)."""
    t = (SHANI / "Modules/Files/FilesPanel.qml").read_text()
    for owner, area in (("cell", "cellArea"), ("row", "rowArea"), ("scell", "scellArea")):
        a = t[t.index(f"id: {area}"):]
        a = a[:a.index("onDoubleClicked")]
        assert "acceptedButtons: Qt.LeftButton | Qt.RightButton" in a, owner
        assert "mouse.button === Qt.RightButton" in a and "win.openMenu(" in a, owner
    assert "background: true" in t and "if (e.background) {" in t
    for label in ("New folder", "Open in terminal", "Turn the selection over", "Set as wallpaper", "Star"):
        assert f'Tr.t("{label}")' in t, label


def test_no_property_declared_twice_in_one_object():
    """Two `property` declarations of one name in the same object stop the whole
    shell loading ("Duplicate property name") - a Viewer `shown` added beside the
    one it had did exactly that. Each object's own declarations, by brace depth."""
    import re
    decl = re.compile(r"^\s*(?:readonly\s+|required\s+|default\s+)*property\s+[\w.<>]+\s+(\w+)")
    bad = []
    for f in SHANI.rglob("*.qml"):
        stack = [{}]
        for n, line in enumerate(f.read_text(errors="replace").splitlines(), 1):
            code = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//.*$', '""', line)
            m = decl.match(code)
            if m:
                seen = stack[-1]
                if m.group(1) in seen:
                    bad.append(f"{f.relative_to(SHANI)}:{n} {m.group(1)} (also line {seen[m.group(1)]})")
                seen.setdefault(m.group(1), n)
            for ch in code:
                if ch == "{":
                    stack.append({})
                elif ch == "}" and len(stack) > 1:
                    stack.pop()
    assert not bad, bad


def test_no_property_set_twice_in_one_object():
    """`kind: "danger"` and `kind: ...` in one Button: "Property value set multiple
    times" - the shell does not load. Each object's own `name:` lines, by depth."""
    import re
    setter = re.compile(r"^\s*([a-z][\w]*(?:\.[a-z]\w*)*)\s*:\s*(?!\s*$)")
    bad = []
    for f in SHANI.rglob("*.qml"):
        stack = [{}]
        in_func = []                                    # depths where a JS function body began
        for n, line in enumerate(f.read_text(errors="replace").splitlines(), 1):
            code = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//.*$', '""', line)
            depth = len(stack)
            m = setter.match(code)
            if m and not in_func and not re.match(r"^\s*(case|default)\b", code):
                seen = stack[-1]
                if m.group(1) in seen:
                    bad.append(f"{f.relative_to(SHANI)}:{n} {m.group(1)} (also line {seen[m.group(1)]})")
                seen.setdefault(m.group(1), n)
            starts_js = bool(re.search(r"(function\b[^{]*|=>\s*|:\s*|\)\s*)\{\s*$", code)) and not re.match(r"^\s*[A-Z]\w*(\.\w+)*\s*\{", code)
            for ch in code:
                if ch == "{":
                    stack.append({})
                elif ch == "}" and len(stack) > 1:
                    stack.pop()
                    if in_func and len(stack) < in_func[-1]:
                        in_func.pop()
            if starts_js and len(stack) > depth:
                in_func.append(len(stack))
    assert not bad, bad[:10]
