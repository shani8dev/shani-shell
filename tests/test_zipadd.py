"""bridge/zipadd.py: adding to a zip, which libarchive cannot do.

bsdtar reads a zip only to write a new one ("Unrecognized archive format" when
it tries to append), so this bridge exists. What is pinned here is the behaviour
that is easy to get wrong: a name already in the archive is *replaced*, not
duplicated; a protected archive is refused rather than rewritten as a readable
one; and the archive is still a valid zip afterwards.
"""

import importlib.util
import sys
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import zipadd  # noqa: E402


def make_zip(path, files):
    with zipfile.ZipFile(path, "w") as z:
        for name, body in files.items():
            z.writestr(name, body)
    return path


def names(path):
    with zipfile.ZipFile(path) as z:
        return z.namelist()


def body(path, name):
    with zipfile.ZipFile(path) as z:
        return z.read(name)


# ---- adding ----------------------------------------------------------------


def test_add_puts_the_file_in(tmp_path):
    arc = make_zip(tmp_path / "a.zip", {"one.txt": "one"})
    src = tmp_path / "two.txt"
    src.write_text("two")
    got = zipadd.cmd_add(str(arc), [str(src)])
    assert got["ok"] is True
    assert names(arc) == ["one.txt", "two.txt"]
    assert body(arc, "two.txt") == b"two"


def test_the_name_is_its_path_from_the_archive_folder(tmp_path):
    # the archive sits in d/, the file in d/sub/ — it is stored as sub/file
    d = tmp_path / "d"
    (d / "sub").mkdir(parents=True)
    arc = make_zip(d / "a.zip", {})
    src = d / "sub" / "file.txt"
    src.write_text("x")
    got = zipadd.cmd_add(str(arc), [str(src)])
    assert got["added"] == ["sub/file.txt"]


def test_a_file_as_given_in_the_callers_folder_is_used(tmp_path, monkeypatch):
    arc = make_zip(tmp_path / "a.zip", {})
    (tmp_path / "b.txt").write_text("b")
    monkeypatch.chdir(tmp_path)
    got = zipadd.cmd_add(str(arc), ["b.txt"])
    assert got["added"] == ["b.txt"]


def test_a_name_already_there_is_replaced_not_duplicated(tmp_path):
    arc = make_zip(tmp_path / "a.zip", {"one.txt": "first"})
    src = tmp_path / "one.txt"
    src.write_text("second")
    zipadd.cmd_add(str(arc), [str(src)])
    assert names(arc) == ["one.txt"]
    assert body(arc, "one.txt") == b"second"


def test_adding_twice_does_not_grow_the_archive(tmp_path):
    arc = make_zip(tmp_path / "a.zip", {})
    src = tmp_path / "a.txt"
    src.write_text("x")
    zipadd.cmd_add(str(arc), [str(src)])
    before = names(arc)
    zipadd.cmd_add(str(arc), [str(src)])
    assert names(arc) == before


def test_a_missing_file_is_skipped_not_an_error(tmp_path):
    arc = make_zip(tmp_path / "a.zip", {"one.txt": "one"})
    got = zipadd.cmd_add(str(arc), [str(tmp_path / "nope.txt")])
    assert got["ok"] is True and got["added"] == []
    assert names(arc) == ["one.txt"]


def test_the_archive_is_still_valid_after_adding(tmp_path):
    arc = make_zip(tmp_path / "a.zip", {"one.txt": "one"})
    src = tmp_path / "two.txt"
    src.write_text("two")
    zipadd.cmd_add(str(arc), [str(src)])
    assert zipfile.is_zipfile(arc)
    with zipfile.ZipFile(arc) as z:
        assert z.testzip() is None


def test_no_file_is_left_behind(tmp_path):
    arc = make_zip(tmp_path / "a.zip", {"one.txt": "one"})
    src = tmp_path / "two.txt"
    src.write_text("two")
    zipadd.cmd_add(str(arc), [str(src)])
    assert not (tmp_path / "a.zip.shani-add").exists()


# ---- protected archives ----------------------------------------------------


@pytest.mark.skipif(zipfile is None, reason="zipfile missing")
def test_a_protected_archive_is_refused(tmp_path):
    """A password on the zip means the library cannot read it back to rewrite
    it, and rewriting it unencrypted would be worse than saying no."""
    import subprocess

    bsdtar = subprocess.run(
        ["sh", "-c", "command -v bsdtar"], capture_output=True, text=True
    )
    if bsdtar.returncode != 0:
        pytest.skip("bsdtar is not installed")
    arc = tmp_path / "locked.zip"
    src = tmp_path / "a.txt"
    src.write_text("secret")
    made = subprocess.run(
        [
            "bsdtar",
            "--format",
            "zip",
            "--options",
            "zip:encryption=aes256",
            "--passphrase",
            "pw",
            "-cf",
            str(arc),
            str(src),
        ],
        capture_output=True,
        text=True,
    )
    if made.returncode != 0:
        pytest.skip("this libarchive cannot write an encrypted zip")
    got = zipadd.cmd_add(str(arc), [str(src)])
    assert got["error"] == "protected"


# ---- names -----------------------------------------------------------------


def test_names_lists_what_is_in_the_archive(tmp_path):
    arc = make_zip(tmp_path / "a.zip", {"one.txt": "1", "two.txt": "2"})
    assert zipadd.cmd_names(str(arc)) == ["one.txt", "two.txt"]


def test_names_of_a_missing_archive_says_so(tmp_path):
    assert zipadd.cmd_names(str(tmp_path / "no.zip"))["error"] == "no such archive"


# ---- the command line ------------------------------------------------------


def test_the_command_line_answers_json(tmp_path):
    import subprocess

    arc = make_zip(tmp_path / "a.zip", {"one.txt": "1"})
    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/zipadd.py"), "names", str(arc)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0
    assert json.loads(out.stdout) == ["one.txt"]


def test_an_unknown_command_is_refused(tmp_path):
    import subprocess

    out = subprocess.run(
        [sys.executable, str(ROOT / "bridge/zipadd.py"), "nonsense", "a.zip"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 2
    assert "unknown command" in out.stdout


import json  # noqa: E402  (used by the command-line tests)
