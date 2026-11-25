"""Accessibility invariants, read out of the QML itself.

Quickshell shows a WARN when a surface fails to load, but nothing complains when
a control has no accessible name: a screen reader just says "button". These
checks walk every file and every control of a kind, and fail on the ones that
would be silent to AT-SPI - which is how the shell's own a11y suite found real
gaps before.

It is static on purpose: it runs anywhere, catches a control that is never
reached by a test, and names the file and line.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QML = sorted(p for p in (ROOT / "shani").rglob("*.qml") if p.name not in ("Tr.qml",))


def read(p):
    return p.read_text(encoding="utf-8")


def blocks(text, kind):
    """Every `Kind { … }` with its body, by brace matching.

    QML is not Python, but a block is: find the opening brace, count to its
    partner. Good enough to ask "does this control say what it is called".
    """
    out = []
    for m in re.finditer(r"\b" + re.escape(kind) + r"\s*\{", text):
        i = m.end() - 1
        depth = 0
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    line = text.count("\n", 0, m.start()) + 1
                    out.append((line, text[i + 1 : j]))
                    break
    return out


def widgets(kind):
    """(file, line, body) for every control of a kind in the tree."""
    found = []
    for p in QML:
        text = read(p)
        for line, body in blocks(text, kind):
            found.append((p, line, body))
    return found


def names(body):
    """The accessible names a control offers itself."""
    out = []
    for m in re.finditer(r"(?:Accessible\.name|accessibleName)\s*:\s*([^\n]+)", body):
        out.append(m.group(1).strip())
    return out


def has(body, *props):
    """Any of these spellings: Common/TextField re-exports Qt's
    placeholderText as placeholder, and both are in use."""
    return any(
        re.search(r"(?<![\w.])" + re.escape(prop) + r"\s*:", body) for prop in props
    )


# ---- the register ----------------------------------------------------------


def test_the_tree_has_qml():
    assert len(QML) > 100


def test_the_tree_has_controls():
    assert len(widgets("IconButton")) > 20
    assert len(widgets("Button")) > 20


# ---- IconButton ------------------------------------------------------------


@pytest.mark.parametrize("path,line", [(p, l) for p, l, _ in widgets("IconButton")])
def test_every_icon_button_says_which_icon_it_is(path, line):
    """An icon button's only name is its tooltip: without one a screen reader
    says "button" and a person cannot tell what it does."""
    body = dict(((p, l), b) for p, l, b in widgets("IconButton"))[(path, line)]
    assert has(body, "tip") or names(body), f"{path}:{line}"


# ---- Button ----------------------------------------------------------------


@pytest.mark.parametrize("path,line", [(p, l) for p, l, _ in widgets("Button")])
def test_every_button_says_what_it_does(path, line):
    body = dict(((p, l), b) for p, l, b in widgets("Button"))[(path, line)]
    assert has(body, "text", "label") or names(body), f"{path}:{line}"


# ---- Choice ----------------------------------------------------------------


@pytest.mark.parametrize("path,line", [(p, l) for p, l, _ in widgets("Choice")])
def test_every_choice_says_what_it_is(path, line):
    body = dict(((p, l), b) for p, l, b in widgets("Choice"))[(path, line)]
    assert has(body, "text") or names(body) or "modelData" in body, f"{path}:{line}"


# ---- TextField -------------------------------------------------------------


@pytest.mark.parametrize("path,line", [(p, l) for p, l, _ in widgets("TextField")])
def test_every_text_field_says_what_to_type(path, line):
    """A field with no placeholder and no label is "entry" to a screen reader."""
    body = dict(((p, l), b) for p, l, b in widgets("TextField"))[(path, line)]
    assert has(body, "placeholder", "placeholderText", "label") or names(body), (
        f"{path}:{line}"
    )


# ---- SwitchRow / ListRow ---------------------------------------------------


@pytest.mark.parametrize("path,line", [(p, l) for p, l, _ in widgets("SwitchRow")])
def test_every_switch_says_what_it_switches(path, line):
    body = dict(((p, l), b) for p, l, b in widgets("SwitchRow"))[(path, line)]
    assert has(body, "text") or names(body), f"{path}:{line}"


@pytest.mark.parametrize("path,line", [(p, l) for p, l, _ in widgets("ListRow")])
def test_every_list_row_says_what_it_is(path, line):
    body = dict(((p, l), b) for p, l, b in widgets("ListRow"))[(path, line)]
    # thin Common wrappers (SettingRow) extend ListRow without own title/modelData
    if str(path).endswith("/Common/SettingRow.qml"):
        return
    assert has(body, "title") or names(body) or "modelData" in body, f"{path}:{line}"


# ---- windows ---------------------------------------------------------------


@pytest.mark.parametrize("path,line", [(p, l) for p, l, _ in widgets("AppWindow")])
def test_every_app_window_names_itself(path, line):
    """The dock, the switcher and AT-SPI all read this."""
    body = dict(((p, l), b) for p, l, b in widgets("AppWindow"))[(path, line)]
    assert has(body, "appName"), f"{path}:{line}"


# ---- the Accessible attached object ---------------------------------------


@pytest.mark.parametrize("path", [str(p.relative_to(ROOT)) for p in QML])
def test_an_accessible_name_is_never_a_bare_placeholder(path):
    """Accessible.name: "" is worse than none - it overrides the text."""
    text = read(ROOT / path)
    for m in re.finditer(r"(?<![\w.])Accessible\.name\s*:\s*\"\"", text):
        line = text.count("\n", 0, m.start()) + 1
        pytest.fail(f"{path}:{line} sets an empty accessible name")


@pytest.mark.parametrize("path", [str(p.relative_to(ROOT)) for p in QML])
def test_a_role_is_never_on_its_own(path):
    """A role with no name anywhere in the file is a control a screen reader
    cannot identify. The name may be set above or below, so this checks the
    file, not a window around the role."""
    text = read(ROOT / path)
    if "Accessible.role" not in text:
        return
    assert "Accessible.name" in text or "Accessible.description" in text, path


# ---- no control is left with a TODO in its label ---------------------------


@pytest.mark.parametrize("path", [str(p.relative_to(ROOT)) for p in QML])
def test_no_accessible_name_is_a_placeholder(path):
    """Only the name itself - a TODO in a comment is a note, not a label."""
    text = read(ROOT / path)
    for m in re.finditer(r"(?<![\w.])Accessible\.name\s*:\s*\"([^\"]*)\"", text):
        value = m.group(1)
        for bad in ("TODO", "FIXME", "lorem ipsum"):
            assert bad.lower() not in value.lower(), f"{path}: {value}"
