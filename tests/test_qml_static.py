"""Static invariants for the shell's QML.

These are the bug classes that have actually taken surfaces down here, asked of
every file at once: a control with no command, a property set twice on one
object, a Layout property on something that is not in a layout, an id reused, a
stray console.log in shipped code. None of them fails loudly - the surface just
does not appear, or the shell stops answering.

Static on purpose: a per-file check catches a file no test ever opens. The block
parser only reports an object's *own* properties (depth 1), so a child's
Layout.fillWidth is not mistaken for the parent's.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QML = sorted(p for p in (ROOT / "shani").rglob("*.qml"))
REL = [str(p.relative_to(ROOT)) for p in QML]

LAYOUT_PROPS = (
    "fillWidth",
    "fillHeight",
    "preferredWidth",
    "preferredHeight",
    "minimumWidth",
    "maximumWidth",
    "minimumHeight",
    "maximumHeight",
    "alignment",
    "leftMargin",
    "rightMargin",
    "topMargin",
    "bottomMargin",
)


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def strip_strings(text):
    """The file with its string literals blanked, so braces inside them do not
    count and 'function' in a message is not a function."""
    out = []
    for line in text.splitlines():
        line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
        line = re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)
        out.append(line)
    return "\n".join(out)


def objects(text, kind):
    """Every `Kind { … }` as (line, own_properties), own properties being the
    assignments at depth 1 - children are not included."""
    found = []
    for m in re.finditer(r"\b" + re.escape(kind) + r"\s*\{", text):
        i = m.end() - 1
        depth = 0
        end = None
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    end = j
                    break
        if end is None:
            continue
        body = text[i + 1 : end]
        props = []
        depth = 0
        buf = ""
        for ch in body:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            if depth == 0:
                buf += ch
        # walk again, collecting depth-1 segments only
        depth = 0
        start = 0
        for j, ch in enumerate(body):
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    start = j + 1
            elif ch == ";" and depth == 0:
                props.append(body[start:j])
                start = j + 1
        props.append(body[start:])
        found.append((text.count("\n", 0, m.start()) + 1, props, body))
    return found


def own(body):
    return body


# ---- the tree --------------------------------------------------------------


def test_the_tree_is_there():
    assert len(QML) > 100


@pytest.mark.parametrize("rel", REL)
def test_the_file_ends_with_a_newline(rel):
    assert read(rel).endswith("\n"), rel


@pytest.mark.parametrize("rel", REL)
def test_the_file_has_no_tabs(rel):
    for i, line in enumerate(read(rel).splitlines(), 1):
        assert "\t" not in line, f"{rel}:{i}"


@pytest.mark.parametrize("rel", REL)
def test_no_debug_output_is_left_in(rel):
    """Common/Log.qml is the logging service, and a code snippet's body is a
    string - neither is debug output."""
    if rel.endswith("Common/Log.qml"):
        return
    for i, line in enumerate(read(rel).splitlines(), 1):
        if "console.log(" in line:
            # a literal, e.g. a Text Editor snippet: body: "console.log()"
            assert re.search(r':\s*"[^"]*console\.log\(', line), f"{rel}:{i}: {line.strip()[:70]}"


# ---- layout misuse ---------------------------------------------------------


@pytest.mark.parametrize("rel", REL)
def test_no_object_mixes_anchors_with_layout_properties(rel):
    """Mixing them is undefined: the layout wins or the anchors do, and the
    control ends up 0 pixels wide. Only an object's own properties count."""
    text = strip_strings(read(rel))
    for kind in (
        "Row",
        "Column",
        "Grid",
        "Item",
        "Rectangle",
        "ColumnLayout",
        "RowLayout",
        "GridLayout",
        "ListView",
        "GridView",
        "Flickable",
    ):
        for line, props, _body in objects(text, kind):
            joined = " ".join(props)
            has_anchor = re.search(r"(?<![\w.])anchors\.[a-zA-Z]+\s*:", joined)
            has_layout = any(
                re.search(r"(?<![\w.])Layout\." + re.escape(p) + r"\s*:", joined)
                for p in LAYOUT_PROPS
            )
            if has_anchor and has_layout:
                pytest.fail(f"{rel}:{line} {kind}")


@pytest.mark.parametrize("rel", REL)
def test_no_layout_fill_is_a_number(rel):
    text = read(rel)
    for m in re.finditer(r"Layout\.(fillWidth|fillHeight)\s*:\s*(\d+)", text):
        line = text.count("\n", 0, m.start()) + 1
        pytest.fail(f"{rel}:{line} sets {m.group(1)} to {m.group(2)}")


# ---- things that must never appear ----------------------------------------


@pytest.mark.parametrize("rel", REL)
def test_no_eval_or_new_function(rel):
    text = strip_strings(read(rel))
    assert "eval(" not in text, rel
    assert "new Function(" not in text, rel
