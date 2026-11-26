"""Ui.qml only writes properties it declares.

closeAll() kept `scheduled = false` after the Scheduled app moved into Settings
and its property went away. A write to an undeclared name throws in QML, so
closeAll() stopped there: IRC, Health, Cloud sync, Services and Settings were
never closed by "close everything" (qs.log: Invalid write to global property
"scheduled").
"""
from __future__ import annotations

import re
from pathlib import Path

UI = Path(__file__).resolve().parents[1] / "shani/Common/Ui.qml"


def _undeclared_writes(src: str) -> list[tuple[str, int]]:
    declared = set(re.findall(r"^\s*(?:readonly\s+)?property\s+[\w<>.]+\s+(\w+)", src, re.M))
    local = set(re.findall(r"\b(?:const|let|var)\s+(\w+)", src))
    for args in re.findall(r"function\s+\w+\s*\(([^)]*)\)", src):
        local |= {a.split(":")[0].strip() for a in args.split(",") if a.strip()}
    out = []
    for m in re.finditer(r"(?m)^ {8}(\w+)\s*=(?!=)", src):   # statements in the root's functions
        if m.group(1) not in declared | local:
            out.append((m.group(1), src[: m.start()].count("\n") + 1))
    return out


def test_every_write_names_a_declared_property():
    assert _undeclared_writes(UI.read_text()) == []


def test_the_check_sees_a_stale_write():
    src = UI.read_text().replace("        irc = false;", "        irc = false;\n        scheduled = false;", 1)
    assert ("scheduled", src.splitlines().index("        scheduled = false;") + 1) in _undeclared_writes(src)
