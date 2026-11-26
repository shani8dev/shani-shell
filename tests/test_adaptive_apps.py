"""Phone-friendly app windows: a fixed side column must fold into a drawer.

A column with a fixed width beside a filling content pane used to eat a phone's
whole screen (412 px, touch, no keyboard). Common/SidePane is the one way to
fold it: wide, it stays a column; narrow, AppWindow's header menu button opens
it as a drawer over the content. This static check names a file that grows a
new fixed column instead, including files no live check opens.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
MODULES = ROOT / "shani" / "Modules"

# Other branches own these windows right now: they are not part of this change.
OWNED = (
    "shani/Modules/Contacts/",
    "shani/Modules/Calls/",
    "shani/Modules/Messages/",
    "shani/Modules/Health/",
    "shani/Modules/Settings/",
    "shani/Modules/Containers/",
)

# Windows known to carry a side column, so a future rewrite cannot slip past a
# heuristic that only looks for the current spelling of `preferredWidth`.
SIDEBAR_APPS = (
    "shani/Modules/Mail/MailWindow.qml",
    "shani/Modules/Notes/NotesPanel.qml",
    "shani/Modules/Feeds/FeedsWindow.qml",
    "shani/Modules/Irc/IrcWindow.qml",
    "shani/Modules/Photos/PhotosWindow.qml",
    "shani/Modules/MediaPlayer/MediaPlayerWindow.qml",
    "shani/Modules/PdfReader/PdfReader.qml",
    "shani/Modules/Camera/CameraPanel.qml",
    "shani/Modules/Files/FilesPanel.qml",
)


def appwindow_files():
    for p in sorted(MODULES.rglob("*.qml")):
        rel = p.relative_to(ROOT).as_posix()
        if any(rel.startswith(prefix) for prefix in OWNED):
            continue
        text = p.read_text(encoding="utf-8")
        if re.search(r"\bAppWindow\s*\{", text):
            yield rel, text


def block_at(text, opening):
    """The body of a `{` block, by brace matching (strings blanked first)."""
    depth = 0
    for j in range(opening, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1 : j]
    return ""


def blocks(text, kind):
    for m in re.finditer(r"\b" + re.escape(kind) + r"\s*\{", text):
        yield text.count("\n", 0, m.start()) + 1, block_at(text, m.end() - 1)


def strip_strings(text):
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    return re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", text)


def own_props(body):
    """Assignments at the object's own depth, not those of its children."""
    depth = 0
    line = []
    out = []
    for ch in body:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        if depth == 0:
            if ch == ";":
                out.append("".join(line))
                line = []
            else:
                line.append(ch)
    out.append("".join(line))
    return "\n".join(out)


def direct_children(body):
    """Bodies of the objects a row/layout directly contains."""
    depth = 0
    out = []
    for m in re.finditer(r"\b([A-Z]\w*)\s*\{", body):
        opening = m.end() - 1
        if opening < 0:
            continue
        before = body[: opening + 1]
        # an object at depth 1: inside the row's braces, not inside a child's
        level = before.count("{") - before.count("}")
        if level != 1:
            continue
        out.append((m.group(1), block_at(body, opening)))
    return out


# A minimumWidth is a floor, not a fixed column: a pane hidden on compact may
# keep a desktop floor without taking a phone's width. Preferred and plain
# widths are the ones that pin a side pane beside a filling pane.
WIDTH = re.compile(r"(?:Layout\.)?(?:preferredWidth|width)\s*:\s*Theme\.px\((\d+)\)")


def fixed_side_columns(text):
    """(row line, width) for a fixed column beside a pane that fills the row."""
    found = []
    clean = strip_strings(text)
    for kind in ("RowLayout", "Row"):
        for line, body in blocks(clean, kind):
            children = direct_children(body)
            fills = any("Layout.fillWidth: true" in own_props(b) for _, b in children)
            if not fills:
                continue
            for _, child in children:
                props = own_props(child)
                for m in WIDTH.finditer(props):
                    width = int(m.group(1))
                    if 170 <= width <= 360 and "Layout.fillWidth: true" not in props:
                        found.append((line, width))
    return found


@pytest.mark.parametrize(
    "rel,text", list(appwindow_files()), ids=lambda v: v if isinstance(v, str) else ""
)
def test_fixed_width_side_column_is_a_side_pane(rel, text):
    cols = fixed_side_columns(text)
    assert not cols, (
        f"{rel}: a fixed side column beside a filling pane at {cols}; "
        "wrap it in Common/SidePane and set sidePane on the AppWindow"
    )


@pytest.mark.parametrize("rel", SIDEBAR_APPS)
def test_sidebar_apps_have_a_folding_pane(rel):
    text = (ROOT / rel).read_text(encoding="utf-8")
    assert re.search(r"\bSidePane\s*\{", text), f"{rel}: sidebar does not fold"
    assert re.search(r"\bsidePane\s*:\s*(\w+)", text), (
        f"{rel}: AppWindow has no sidePane"
    )
    assert re.search(r"compact\s*:\s*win\.compact", text), (
        f"{rel}: SidePane does not follow the window's compact state"
    )


@pytest.mark.parametrize(
    "rel,text", list(appwindow_files()), ids=lambda v: v if isinstance(v, str) else ""
)
def test_a_declared_side_pane_is_wired_and_compact(rel, text):
    if "SidePane {" not in text:
        return
    m = re.search(r"\bsidePane\s*:\s*(\w+)", text)
    assert m, f"{rel}: SidePane declared but AppWindow does not know it"
    assert re.search(rf"\bid\s*:\s*{m.group(1)}\b", text), (
        f"{rel}: sidePane points at an id that does not exist"
    )
    assert "compact: win.compact" in text, (
        f"{rel}: the drawer never opens on a narrow window"
    )
