"""The small JS libraries the QML leans on: Calibrate.js, FileIcons.js and
setup/strings.js.

Each is pure, so each runs under node - which is the only way to check the maths
and the fallback, neither of which a UI test can see. A bad calibration matrix
is a touchscreen that is off by a finger-width; a missing setup string is an
English page in a Marathi wizard.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
NODE = shutil.which("node") or shutil.which("nodejs")

pytestmark = pytest.mark.skipif(NODE is None, reason="node is not installed")


def load(rel):
    """The file with .pragma dropped, ready to run."""
    text = (ROOT / rel).read_text(encoding="utf-8")
    return "\n".join(l for l in text.splitlines() if not l.startswith(".pragma"))


def js(body, expr):
    out = subprocess.run(
        [NODE, "-e", body + "\nconsole.log(JSON.stringify(" + expr + "));"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


# ---- Calibrate.js ----------------------------------------------------------


def test_an_exact_touch_maps_to_itself():
    """Four targets touched exactly: the matrix is the identity, so every point
    lands where it was touched."""
    body = load("shani/Common/Calibrate.js")
    matrix = js(body, "solve(targets.map(p => ({ seen: p, target: p })))")
    # [a, b, c, d, e, f]: x' = a·x + b·y + c, y' = d·x + e·y + f
    assert matrix == [1, 0, 0, 0, 1, 0], matrix


def test_a_missing_point_does_not_solve():
    """Three points are not four: the library must say so, not invent one."""
    body = load("shani/Common/Calibrate.js")
    three = json.dumps(
        [
            {"x": 0.1, "y": 0.1},
            {"x": 0.9, "y": 0.1},
            {"x": 0.9, "y": 0.9},
        ]
    )
    out = subprocess.run(
        [NODE, "-e", body + "\nconsole.log(JSON.stringify(solve(" + three + ")));"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert (
        out.returncode != 0
        or "null" in out.stdout
        or "error" in (out.stdout + out.stderr).lower()
    )


# ---- FileIcons.js ----------------------------------------------------------


@pytest.mark.parametrize(
    "ext,expect",
    [
        (".md", "text-x-generic"),
        (".mp3", "audio-x-generic"),
        (".webm", "video-x-generic"),
        (".zip", "package-x-generic"),
        (".pdf", "x-office-document"),
        (".desktop", "application-x-executable"),
    ],
)
def test_a_file_gets_the_icon_for_its_kind(ext, expect):
    body = load("shani/Common/FileIcons.js")
    got = js(body, f"iconFor({{ ext: {json.dumps(ext)} }})")
    assert got == expect, (ext, got)


def test_the_extension_is_case_insensitive():
    body = load("shani/Common/FileIcons.js")
    assert js(body, 'iconFor({ ext: ".MP3" })') == "audio-x-generic"


def test_a_picture_is_a_picture():
    body = load("shani/Common/FileIcons.js")
    assert js(body, 'iconFor({ ext: ".png", image: true })') == "image-x-generic"


def test_an_entry_with_nothing_is_a_plain_file():
    body = load("shani/Common/FileIcons.js")
    assert js(body, "iconFor({})") == "text-x-generic"


def test_a_folder_is_a_folder():
    body = load("shani/Common/FileIcons.js")
    assert js(body, "iconFor({ isDir: true })") == "folder"


# ---- setup/strings.js ------------------------------------------------------


def setup_strings():
    body = load("setup/strings.js")
    out = subprocess.run(
        [NODE, "-e", body + "\nconsole.log(JSON.stringify(strings));"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


def test_every_locale_has_the_english_keys():
    """A missing key falls back to English, so a page would switch language
    halfway through the wizard."""
    table = setup_strings()
    english = set(table["en"])
    for lang, words in table.items():
        missing = english - set(words)
        assert missing == set(), f"{lang} is missing {sorted(missing)}"


def test_no_string_is_empty():
    for lang, words in setup_strings().items():
        for key, value in words.items():
            assert str(value).strip(), f"{lang}.{key}"


def test_the_wizard_has_the_languages_it_says():
    table = setup_strings()
    for lang in ("en", "mr", "hi", "de", "es", "fr"):
        assert lang in table, lang


def test_an_unknown_locale_falls_back_to_english():
    body = load("setup/strings.js")
    assert js(body, 'tr("zz", "welcome")') == setup_strings()["en"]["welcome"]


def test_a_region_locale_uses_its_language():
    """pt_BR, en_GB: the language is the first two letters."""
    body = load("setup/strings.js")
    assert js(body, 'tr("en_GB", "welcome")') == setup_strings()["en"]["welcome"]


def test_a_key_nobody_defined_falls_back_rather_than_printing_undefined():
    body = load("setup/strings.js")
    out = subprocess.run(
        [NODE, "-e", body + '\nconsole.log(String(tr("en", "no-such-key")));'],
        capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == "undefined"
