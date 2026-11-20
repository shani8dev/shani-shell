"""bridge/copyjob.py - TeraCopy's features on real files: verify, the rules for a
name already there (replaced ones to the trash), a bad file passed over and
retried by itself, pause/resume, speed, history, checksums made and tested."""
import hashlib
import importlib.util
import io
import json
import os
import signal
import threading
import time
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("copyjob", Path(__file__).resolve().parent.parent / "bridge" / "copyjob.py")
cj = importlib.util.module_from_spec(spec); spec.loader.exec_module(cj)


@pytest.fixture(autouse=True)
def env(tmp_path, monkeypatch):
    old = (signal.getsignal(signal.SIGTERM), signal.getsignal(signal.SIGUSR1))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    trash = tmp_path / "trash"; trash.mkdir()
    # gio trash stands in: moved into tmp/trash, as the real one keeps it
    monkeypatch.setattr(cj.Job, "_to_trash", staticmethod(lambda p: os.rename(p, trash / (os.path.basename(p) + ".%d" % time.time_ns()))))
    yield
    signal.signal(signal.SIGTERM, old[0]); signal.signal(signal.SIGUSR1, old[1])


def run(dest, mode, paths, **opts):
    out = io.StringIO()
    cj.Job(out=out, chunk=4096, opts=opts).run(str(dest), mode, [str(p) for p in paths])
    return [json.loads(l) for l in out.getvalue().splitlines()]


def test_verify_counts_every_file(tmp_path):
    s = tmp_path / "s"; (s / "d").mkdir(parents=True); (s / "a").write_bytes(os.urandom(50000)); (s / "d" / "b").write_text("b")
    dest = tmp_path / "dest"; dest.mkdir()
    res = run(dest, "copy", [s / "a", s / "d"], verify=True)[-1]
    assert res["verified"] == 2 and not res["failed"]
    assert (dest / "a").read_bytes() == (s / "a").read_bytes()
    assert not list(dest.glob(".*shani-part"))


def test_verify_catches_a_bad_copy(tmp_path, monkeypatch):
    s = tmp_path / "a"; s.write_bytes(b"x" * 10000)
    dest = tmp_path / "dest"; dest.mkdir()
    monkeypatch.setattr(cj.Job, "_digest", lambda self, p: "not the same")
    res = run(dest, "copy", [s], verify=True)[-1]
    assert res["failed"][0]["error"].startswith("the copy does not match") and not (dest / "a").exists()


def test_move_with_verify_keeps_the_source_of_a_bad_copy(tmp_path, monkeypatch):
    s = tmp_path / "src"; s.mkdir(); (s / "a").write_text("a"); (s / "b").write_text("b")
    dest = tmp_path / "dest"; dest.mkdir()
    real = os.stat
    other = type("S", (), {"st_dev": -1, "st_ino": 0})()
    monkeypatch.setattr(cj.os, "stat", lambda p, *a, **k: other if str(p) == str(dest) else real(p, *a, **k))
    good = cj.Job._digest
    monkeypatch.setattr(cj.Job, "_digest", lambda self, p: "bad" if p.endswith(".b.shani-part") else good(self, p))
    res = run(dest, "move", [s], verify=True)[-1]
    assert [f["path"] for f in res["failed"]] == [str(s / "b")]
    assert not (s / "a").exists() and (s / "b").read_text() == "b"          # only the proven one left its place
    assert (dest / "src" / "a").read_text() == "a" and res["pairs"][0][2] == "moved-partly"


@pytest.mark.parametrize("rule,expect,replaced,skipped", [
    ("skip", "old", 0, 1), ("replace", "new", 1, 0), ("older", "new", 1, 0), ("differs", "new", 1, 0)])
def test_conflict_rules(tmp_path, rule, expect, replaced, skipped):
    s = tmp_path / "s"; s.mkdir(); (s / "f.txt").write_text("new")
    dest = tmp_path / "dest"; dest.mkdir(); (dest / "f.txt").write_text("old")
    os.utime(dest / "f.txt", (1000, 1000))
    res = run(dest, "copy", [s / "f.txt"], conflict=rule)[-1]
    assert (dest / "f.txt").read_text() == expect and res["replaced"] == replaced and res["skipped"] == skipped
    if replaced:
        assert [p.read_text() for p in (tmp_path / "trash").iterdir()] == ["old"]     # can be put back


def test_older_and_differs_leave_the_same_file(tmp_path):
    s = tmp_path / "s"; s.mkdir(); (s / "f").write_text("same")
    dest = tmp_path / "dest"; dest.mkdir(); (dest / "f").write_text("same")
    t = (s / "f").stat().st_mtime; os.utime(dest / "f", (t, t))
    for rule in ("older", "differs"):
        assert run(dest, "copy", [s / "f"], conflict=rule)[-1]["skipped"] == 1


def test_folders_merge_under_a_rule(tmp_path):
    s = tmp_path / "Photos"; s.mkdir(); (s / "new.jpg").write_text("n"); (s / "same.jpg").write_text("s2")
    dest = tmp_path / "dest"; (dest / "Photos").mkdir(parents=True); (dest / "Photos" / "same.jpg").write_text("s1"); (dest / "Photos" / "keep.jpg").write_text("k")
    res = run(dest, "copy", [s], conflict="skip")[-1]
    assert sorted(p.name for p in (dest / "Photos").iterdir()) == ["keep.jpg", "new.jpg", "same.jpg"]
    assert (dest / "Photos" / "same.jpg").read_text() == "s1" and res["skipped"] == 1
    assert not (dest / "Photos (2)").exists()


def test_a_bad_file_is_passed_over_and_retried_alone(tmp_path):
    s = tmp_path / "s"; s.mkdir(); (s / "a").write_text("a"); (s / "locked").write_text("x"); (s / "z").write_text("z")
    os.chmod(s / "locked", 0)
    if os.access(s / "locked", os.R_OK):
        pytest.skip("running as root: nothing is unreadable")
    dest = tmp_path / "dest"; dest.mkdir()
    res = run(dest, "copy", [s])[-1]
    assert sorted(p.name for p in (dest / "s").iterdir()) == ["a", "z"]      # the rest still copied
    assert [(f["path"], f["target"]) for f in res["failed"]] == [(str(s / "locked"), str(dest / "s" / "locked"))]
    os.chmod(s / "locked", 0o644)
    res = run(dest, "copy", [], pairs=[[f["path"], f["target"]] for f in res["failed"]])[-1]
    assert not res["failed"] and (dest / "s" / "locked").read_text() == "x"


def test_pause_and_resume(tmp_path):
    s = tmp_path / "big"; s.write_bytes(os.urandom(2 << 20))
    dest = tmp_path / "dest"; dest.mkdir()
    out = io.StringIO()
    job = cj.Job(out=out, chunk=4096, opts={})
    job.paused = True                                           # as SIGUSR1 would
    threading.Timer(0.5, lambda: setattr(job, "paused", False)).start()
    t0 = time.monotonic(); job.run(str(dest), "copy", [str(s)])
    ls = [json.loads(l) for l in out.getvalue().splitlines()]
    assert time.monotonic() - t0 >= 0.45
    assert {"paused": False} in ls and any(l.get("paused") is True for l in ls)
    assert (dest / "big").read_bytes() == s.read_bytes()
    assert any("rate" in l for l in ls)


def test_history_is_written(tmp_path):
    s = tmp_path / "a"; s.write_text("a"); dest = tmp_path / "d"; dest.mkdir()
    run(dest, "copy", [s])
    h = cj.history()
    assert h[0]["mode"] == "copy" and h[0]["done"] == 1 and h[0]["names"] == ["a"]


def test_checksums_made_and_tested(tmp_path):
    d = tmp_path / "iso"; d.mkdir(); (d / "a.iso").write_bytes(b"A" * 9000); (d / "b.iso").write_bytes(b"B")
    out = io.StringIO()
    cj.Job(out=out).make_sums(str(d / "SHA256SUMS.sha256"), [str(d)])
    res = json.loads(out.getvalue().splitlines()[-1])
    text = Path(res["saved"]).read_text()
    assert text == "%s  a.iso\n%s  b.iso\n" % (hashlib.sha256(b"A" * 9000).hexdigest(), hashlib.sha256(b"B").hexdigest())
    out = io.StringIO(); cj.Job(out=out).check_sums(res["saved"])
    assert json.loads(out.getvalue().splitlines()[-1])["good"] == 2
    (d / "b.iso").write_bytes(b"changed"); (d / "a.iso").unlink()
    out = io.StringIO(); cj.Job(out=out).check_sums(res["saved"])
    r = json.loads(out.getvalue().splitlines()[-1])
    assert r["bad"] == [str(d / "b.iso")] and r["missing"] == [str(d / "a.iso")] and "error" in r
