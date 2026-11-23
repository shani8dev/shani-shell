"""Static + unit checks for the Shelf / StartHints fixes.

Shelf.qml and StartHints.qml are QML singletons, so their logic is checked the
way the other shell helpers are: a small extraction run in node plus source
assertions for the wiring that cannot be executed outside Quickshell.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHELF = ROOT / "shani/Services/Shelf.qml"
HINTS = ROOT / "shani/Modules/Hints/StartHints.qml"


def _clean_path_source():
    src = SHELF.read_text(encoding="utf-8")
    match = re.search(r"function cleanPath\(p\) \{[\s\S]*?\n    \}", src)
    assert match, "Shelf.qml has no cleanPath()"
    return match.group(0)


def test_park_normalises_only_file_uris_and_survives_bad_escapes():
    """A plain path with a '%' is data, not a broken escape; a bad URI must not
    abort the whole drop. This is the node-executed unit check for cleanPath()."""
    node = shutil.which("node")
    if node is None:
        pytest.skip("node is not installed")
    prog = (
        _clean_path_source()
        + r"""
    process.stdout.write(JSON.stringify({
        plain: cleanPath("/home/me/50% done.txt"),
        uri: cleanPath("file:///home/me/a%20b.txt"),
        bad: cleanPath("file:///home/me/100% done.txt")
    }));"""
    )
    result = subprocess.run([node, "-e", prog], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    out = json.loads(result.stdout)
    assert out["plain"] == "/home/me/50% done.txt"  # never decoded
    assert out["uri"] == "/home/me/a b.txt"  # real URI decoded
    assert out["bad"] == "/home/me/100% done.txt"  # malformed escape kept, no throw


def test_park_uses_the_normaliser_and_deduplicates_a_batch():
    src = SHELF.read_text(encoding="utf-8")
    assert 'const add = [].concat(paths).map(cleanPath).filter(p => p !== "");' in src
    assert "const unique = add.filter((p, i) => add.indexOf(p) === i);" in src
    assert "unique.indexOf(p) < 0" in src
    # the old blanket decodeURIComponent on every input is gone
    assert ".map(p => decodeURIComponent(p))" not in src
    assert 'replace(/^file:\\/\\//, "")' not in src


def test_unpark_normalises_before_removing():
    src = SHELF.read_text(encoding="utf-8")
    assert "function unpark(path) {\n        const p = cleanPath(path);" in src
    assert "root.parked.filter(x => x !== p)" in src


def test_refresh_does_not_stack_overlapping_scans():
    src = SHELF.read_text(encoding="utf-8")
    assert "function refresh() { if (!list.running) list.running = true; }" in src


def test_thumbnails_cover_the_formats_the_shell_claims():
    src = SHELF.read_text(encoding="utf-8")
    line = next(l for l in src.splitlines() if "image: /\\." in l)
    for ext in ("avif", "heic", "bmp", "svg"):
        assert ext in line, line
    assert "webp|gif)$/i" not in line


def test_start_hints_wait_for_the_first_login_tour():
    src = HINTS.read_text(encoding="utf-8")
    visible = src.split("visible:", 1)[1].split("implicitWidth:", 1)[0]
    assert "!Ui.tour" in visible
    assert "Settings.data.tourEnabled" in visible
    assert "Settings.data.tourSeen" in visible
    assert 'Quickshell.env("SHANI_NO_TOUR")' in visible


def test_start_hints_teach_the_lens_shortcut():
    src = HINTS.read_text(encoding="utf-8")
    assert 'keys: "Super + S"' in src
    assert "read, scan or ask about anything on screen" in src
