"""Design drift gates: one owner for every look and every shared behaviour.

Theme.qml owns colour, size and shape; Common/ owns the widgets; Services own
the data readers. These checks fail when a surface grows a private copy again:

- bans (count must stay 0): patterns that were copied and drifted into bugs
- ratchets (count may only go down): literal design values that predate the
  tokens. Lower the number when you remove some; never raise it - use a Theme
  token, a Common widget or Theme.inkOn() instead.
"""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def qml_files():
    # greeter/Common and setup/Common are symlinks to shani/Common: count once
    for top in ("shani", "greeter", "setup"):
        for p in sorted((ROOT / top).rglob("*.qml")):
            if any(part == "Common" for part in p.relative_to(ROOT).parts[1:]) and top != "shani":
                continue
            yield p


def hits(pattern, skip=()):
    rx = re.compile(pattern)
    out = []
    for p in qml_files():
        rel = p.relative_to(ROOT).as_posix()
        if rel in skip:
            continue
        for n, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            if rx.search(line):
                out.append(f"{rel}:{n}: {line.strip()[:100]}")
    return out


# ---- bans -------------------------------------------------------------------

BANS = {
    # a colour picked by the style instead of a semantic token: skips the
    # light/dark cross-fade and high contrast (Theme.mix / Theme.inkOn / a token)
    "mode-branch colour": (r'\bdark\s*\?\s*"#', ()),
    # the nine tools open through Ui.openTool; four surfaces once carried their
    # own copy of the same nine closures
    "local tool opener table": (r"\btoolRuns\b", ()),
    # recently-used.xbel has one reader (Services/RecentFiles); the overview's
    # private copy lost the newest-first sort
    "private recent-files parser": (r"<bookmark\[", ("shani/Services/RecentFiles.qml",)),
    # markup marks are drawn by Common/Markup.js; PdfReader's copy drew saved
    # pen strokes by the tool picked now
    "private markup drawing": (r"function mark\(ctx", ()),
}


@pytest.mark.parametrize("name", sorted(BANS))
def test_banned_copies_stay_gone(name):
    pattern, skip = BANS[name]
    found = hits(pattern, skip)
    assert not found, f"{name}:\n" + "\n".join(found)


# ---- ratchets ---------------------------------------------------------------
# name: (pattern, skip, ceiling measured 2026-11-25)

RATCHETS = {
    # hex / Qt.rgba colours outside the theme. Most left are content colours
    # (ruler ticks, video black, map ink) - move any UI colour to a token
    "literal colour": (r'"#[0-9a-fA-F]{3,8}"|Qt\.rgba?\(', ("shani/Common/Theme.qml",), 80),
    # radius: N instead of Theme.radius / radiusSmall / radiusLarge
    "literal radius": (r"\bradius:\s*[1-9][0-9]*\s*($|;|//)", (), 54),
    # font.pixelSize: N instead of Theme.px(N) * Theme.fontScale (ignores the
    # person's text size)
    "literal font size": (r"font\.pixelSize:\s*[0-9]+\s*($|;|//)", (), 3),
}


@pytest.mark.parametrize("name", sorted(RATCHETS))
def test_literal_design_values_only_go_down(name):
    pattern, skip, ceiling = RATCHETS[name]
    found = hits(pattern, skip)
    assert len(found) <= ceiling, (
        f"{name}: {len(found)} > {ceiling}. Use a Theme token instead; newest hits:\n"
        + "\n".join(found[-10:])
    )


def test_error_rows_use_the_shared_banner():
    # a dismissable error is an InfoBanner (tone, icon, AlertMessage role,
    # translated actions), not a hand-built Text + Button row
    for rel in ("shani/Modules/NetTools.qml", "shani/Modules/Teleprompter.qml",
                "shani/Modules/TextEditor/TextEditorPanel.qml"):
        src = (ROOT / rel).read_text()
        assert "InfoBanner {" in src, rel
        assert 'text: "Dismiss"' not in src, rel
