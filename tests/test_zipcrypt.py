"""bridge/zipcrypt.py: password-protected zips through libarchive.

This is the one place in the shell that writes files out of an archive someone
else made, so the tests are mostly about what must *not* happen: a name that
climbs out of the destination is not written, a wrong password leaves nothing
behind, and a half-finished extraction is taken back rather than left lying
there. Round-tripping a real archive proves the encryption itself.
"""

import os
import sys
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import zipcrypt  # noqa: E402

libarchive = pytest.mark.skipif(
    zipcrypt.ctypes.util.find_library("archive") is None,
    reason="libarchive is not installed",
)


def make_plain(path, files):
    with zipfile.ZipFile(path, "w") as z:
        for name, body in files.items():
            z.writestr(name, body)
    return path


# ---- reading whether an archive is protected -------------------------------


@libarchive
def test_a_plain_zip_is_not_encrypted(tmp_path):
    arc = make_plain(tmp_path / "a.zip", {"one.txt": "one"})
    assert zipcrypt.encrypted(str(arc)) is False


@libarchive
def test_an_archive_this_module_made_is_encrypted(tmp_path):
    arc = tmp_path / "e.zip"
    src = tmp_path / "one.txt"
    src.write_text("secret")
    got = zipcrypt.make(str(arc), [str(src)], "pw")
    assert got.get("ok") is True or got.get("saved")
    assert zipcrypt.encrypted(str(arc)) is True


@libarchive
def test_a_file_that_is_not_a_zip_is_not_encrypted(tmp_path):
    junk = tmp_path / "junk.zip"
    junk.write_text("not a zip at all")
    assert zipcrypt.encrypted(str(junk)) is False


# ---- the round trip ---------------------------------------------------------


@libarchive
def test_make_then_extract_returns_the_same_bytes(tmp_path):
    src = tmp_path / "one.txt"
    src.write_text("secret content\n")
    arc = tmp_path / "e.zip"
    zipcrypt.make(str(arc), [str(src)], "pw")
    out = tmp_path / "out"
    got = zipcrypt.extract(str(arc), str(out), "pw")
    assert got == {"saved": str(out)}
    assert (out / "one.txt").read_text() == "secret content\n"


@libarchive
def test_a_wrong_password_says_so(tmp_path):
    src = tmp_path / "one.txt"
    src.write_text("secret")
    arc = tmp_path / "e.zip"
    zipcrypt.make(str(arc), [str(src)], "pw")
    out = tmp_path / "out"
    assert zipcrypt.extract(str(arc), str(out), "not-pw") == {"wrongPassword": True}


@libarchive
def test_a_wrong_password_leaves_nothing_behind(tmp_path):
    """Half a decrypted file is worse than none: it looks like a real file."""
    src = tmp_path / "one.txt"
    src.write_text("secret")
    arc = tmp_path / "e.zip"
    zipcrypt.make(str(arc), [str(src)], "pw")
    out = tmp_path / "out"
    zipcrypt.extract(str(arc), str(out), "not-pw")
    assert not out.exists() or not any(out.iterdir())


# ---- names that climb out ---------------------------------------------------


@libarchive
def test_a_name_that_climbs_out_is_not_written(tmp_path):
    """A zip is someone else's data: ../ and absolute names are dropped."""
    dest = tmp_path / "dest"
    outside = tmp_path / "escaped.txt"
    arc = tmp_path / "evil.zip"
    with zipfile.ZipFile(arc, "w") as z:
        z.writestr("../escaped.txt", "got out")
        z.writestr("/abs.txt", "absolute")
        z.writestr("ok.txt", "fine")
    got = zipcrypt.extract(str(arc), str(dest), "")
    assert got == {"saved": str(dest)}
    assert (dest / "ok.txt").read_text() == "fine"
    assert not outside.exists()
    assert not Path("/abs.txt").exists()


@libarchive
def test_a_nested_name_stays_inside_the_destination(tmp_path):
    dest = tmp_path / "dest"
    arc = tmp_path / "n.zip"
    with zipfile.ZipFile(arc, "w") as z:
        z.writestr("a/b/c.txt", "deep")
    zipcrypt.extract(str(arc), str(dest), "")
    assert (dest / "a" / "b" / "c.txt").read_text() == "deep"


# ---- taking back ------------------------------------------------------------


@libarchive
def test_take_back_removes_only_what_it_wrote(tmp_path):
    dest = tmp_path / "dest"
    dest.mkdir()
    (dest / "kept.txt").write_text("keep me")
    made = [str(dest / "gone.txt")]
    Path(made[0]).write_text("x")
    zipcrypt._take_back(str(dest), made)
    assert not Path(made[0]).exists()
    assert (dest / "kept.txt").read_text() == "keep me"


# ---- the command line -------------------------------------------------------


def run_cli(*args, password=""):
    import subprocess

    return subprocess.run(
        [sys.executable, str(ROOT / "bridge/zipcrypt.py"), *args],
        input=password,
        capture_output=True,
        text=True,
        timeout=60,
    )


@libarchive
def test_the_command_line_makes_and_reports(tmp_path):
    src = tmp_path / "one.txt"
    src.write_text("x")
    arc = tmp_path / "e.zip"
    out = run_cli("make", str(arc), str(src), password="pw")
    assert out.returncode == 0
    assert zipcrypt.encrypted(str(arc)) is True


@libarchive
def test_the_command_line_reports_a_wrong_password(tmp_path):
    src = tmp_path / "one.txt"
    src.write_text("x")
    arc = tmp_path / "e.zip"
    zipcrypt.make(str(arc), [str(src)], "pw")
    out = run_cli("extract", str(arc), str(tmp_path / "out"), password="bad")
    assert "wrongPassword" in out.stdout


@libarchive
def test_encrypted_answers_json(tmp_path):
    arc = make_plain(tmp_path / "a.zip", {"one.txt": "1"})
    out = run_cli("encrypted", str(arc))
    assert out.returncode == 0
    assert '"encrypted": false' in out.stdout
