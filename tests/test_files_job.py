"""bridge/files.py job: a copy or move that says how far it is and can be stopped.

Real files on disk; cancelling is a real SIGTERM to this process (the handler
job() installs) sent as soon as the job says its total, so it lands on the
first chunk - the half-written item must be gone, the source untouched."""
import importlib.util
import io
import json
import os
import signal
from pathlib import Path

import pytest

BRIDGE = Path(__file__).resolve().parent.parent / "bridge"
spec = importlib.util.spec_from_file_location("files_job", BRIDGE / "files.py")
files = importlib.util.module_from_spec(spec)
spec.loader.exec_module(files)


def lines(buf):
    return [json.loads(l) for l in buf.getvalue().splitlines()]


@pytest.fixture(autouse=True)
def restore_sigterm():
    old = signal.getsignal(signal.SIGTERM)
    yield
    signal.signal(signal.SIGTERM, old)


def tree(tmp_path):
    src = tmp_path / "src"; (src / "album" / "inner").mkdir(parents=True)
    (src / "big.bin").write_bytes(os.urandom(3 << 20))
    (src / "album" / "a.jpg").write_bytes(b"x" * 5000)
    (src / "album" / "inner" / "b.txt").write_text("hello")
    os.symlink("a.jpg", src / "album" / "link")
    dest = tmp_path / "dest"; dest.mkdir()
    (dest / "big.bin").write_text("already here")       # the name is taken
    return src, dest


def test_copy_says_its_total_and_the_result(tmp_path):
    src, dest = tree(tmp_path)
    out = io.StringIO()
    files.job(str(dest), "copy", [str(src / "big.bin"), str(src / "album")], out=out, chunk=64 << 10)
    ls = lines(out)
    assert ls[0] == {"total": (3 << 20) + 5000 + 5 + len("a.jpg"), "items": 2}
    res = ls[-1]
    assert res["mode"] == "copy" and "error" not in res and "cancelled" not in res
    assert res["pairs"] == [[str(src / "big.bin"), str(dest / "big (2).bin"), "copied"], [str(src / "album"), str(dest / "album"), "copied"]]
    assert (dest / "big.bin").read_text() == "already here"                 # never written over
    assert (dest / "big (2).bin").read_bytes() == (src / "big.bin").read_bytes()
    assert (dest / "album" / "inner" / "b.txt").read_text() == "hello"
    assert os.readlink(dest / "album" / "link") == "a.jpg"                  # a link stays a link
    assert (src / "album").exists()


def test_move_on_the_same_drive_is_a_rename(tmp_path):
    src, dest = tree(tmp_path)
    ino = (src / "album").stat().st_ino
    out = io.StringIO()
    files.job(str(dest), "move", [str(src / "album")], out=out)
    assert lines(out)[0]["total"] == 0                                       # nothing to copy
    assert (dest / "album").stat().st_ino == ino and not (src / "album").exists()


class KillOnTotal(io.StringIO):
    def write(self, s):
        n = super().write(s)
        if '"total"' in s:
            os.kill(os.getpid(), signal.SIGTERM)
        return n


def test_cancel_removes_the_half_written_one_only(tmp_path):
    src, dest = tree(tmp_path)
    out = KillOnTotal()
    files.job(str(dest), "copy", [str(src / "big.bin")], out=out, chunk=64 << 10)
    res = lines(out)[-1]
    assert res["cancelled"] is True and res["pairs"] == []
    assert sorted(p.name for p in dest.iterdir()) == ["big.bin"]             # no "big (2).bin" left
    assert (src / "big.bin").stat().st_size == 3 << 20


def test_cancelled_move_leaves_the_source(tmp_path, monkeypatch):
    src, dest = tree(tmp_path)
    out = KillOnTotal()
    # across drives is a copy then a removal: the destination says it is another drive
    real = os.stat
    other = type("S", (), {"st_dev": -1, "st_ino": 0})()
    monkeypatch.setattr(files.os, "stat", lambda p, *a, **k: other if str(p) == str(dest) else real(p, *a, **k))
    files.job(str(dest), "move", [str(src / "album")], out=out, chunk=1024)
    assert lines(out)[-1]["cancelled"] is True
    assert (src / "album" / "a.jpg").exists() and not (dest / "album").exists()


def test_not_into_itself(tmp_path):
    src, dest = tree(tmp_path)
    out = io.StringIO()
    files.job(str(src / "album" / "inner"), "copy", [str(src / "album")], out=out)
    assert lines(out)[-1]["error"] == "a folder cannot go inside itself"


def test_auto_moves_on_the_same_drive_and_copies_from_another(tmp_path, monkeypatch):
    src, dest = tree(tmp_path)
    usb = tmp_path / "usb"; usb.mkdir(); (usb / "photo.jpg").write_bytes(b"p" * 100)
    real = os.stat
    other = type("S", (), {"st_dev": -1, "st_ino": 0})()
    monkeypatch.setattr(files.os, "stat", lambda p, *a, **k: other if str(p) == str(usb) else real(p, *a, **k))
    out = io.StringIO()
    files.job(str(dest), "auto", [str(src / "album"), str(usb / "photo.jpg")], out=out)
    res = lines(out)[-1]
    assert [x[2] for x in res["pairs"]] == ["moved", "copied"]
    assert not (src / "album").exists() and (dest / "album" / "a.jpg").exists()
    assert (usb / "photo.jpg").exists() and (dest / "photo.jpg").read_bytes() == b"p" * 100
