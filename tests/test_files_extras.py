"""bridge/files.py: stars (and the starred: folder), templates, rights with their
undo, and free space - on real files in a scratch home."""
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "files.py"


def run(*args, home):
    env = dict(os.environ, HOME=str(home), XDG_DATA_HOME=str(home / ".local/share"))
    return json.loads(subprocess.run([sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env).stdout)


def test_stars_and_the_starred_folder(tmp_path):
    a = tmp_path / "a.txt"; a.write_text("a"); d = tmp_path / "Photos"; d.mkdir()
    run("star-add", str(a), str(d), home=tmp_path)
    run("star-add", str(a), home=tmp_path)                                   # once only
    assert run("starred-list", home=tmp_path)["starred"] == [str(a), str(d)]
    names = [e["name"] for e in run("list", "starred:", home=tmp_path)["entries"]]
    assert sorted(names) == ["Photos", "a.txt"]
    a.unlink()                                                               # gone: not listed
    assert [e["name"] for e in run("list", "starred:", home=tmp_path)["entries"]] == ["Photos"]
    run("star-remove", str(d), home=tmp_path)
    assert run("starred-list", home=tmp_path)["starred"] == [str(a)]


def test_templates_from_the_xdg_folder(tmp_path):
    (tmp_path / ".config").mkdir()
    (tmp_path / ".config/user-dirs.dirs").write_text('XDG_TEMPLATES_DIR="$HOME/Vorlagen"\n')
    (tmp_path / "Vorlagen").mkdir(); (tmp_path / "Vorlagen/Letter.odt").write_text("x"); (tmp_path / "Vorlagen/.hidden").write_text("")
    r = run("templates", home=tmp_path)
    assert r["templates"] == [{"name": "Letter", "path": str(tmp_path / "Vorlagen/Letter.odt")}]


def test_rights_and_their_undo(tmp_path):
    f = tmp_path / "run.sh"; f.write_text("#!/bin/sh\n"); f.chmod(0o644)
    r = run("chmod-pairs", json.dumps([[str(f), 0o755]]), home=tmp_path)
    assert stat.S_IMODE(f.stat().st_mode) == 0o755 and r["pairs"] == [[str(f), 0o644]]
    run("chmod-pairs", json.dumps(r["pairs"]), home=tmp_path)                # the undo
    assert stat.S_IMODE(f.stat().st_mode) == 0o644


def test_free_space(tmp_path):
    r = run("free", str(tmp_path), home=tmp_path)
    assert 0 < r["free"] <= r["total"]


def test_every_file_of_a_kind(tmp_path):
    """kind:pictures and the others: every one under home, not in hidden folders
    or build output; newest first."""
    import importlib.util, os, time
    spec = importlib.util.spec_from_file_location("fb_kind", Path(__file__).resolve().parent.parent / "bridge" / "files.py")
    fb = importlib.util.module_from_spec(spec); spec.loader.exec_module(fb)
    for rel in ("Pictures/a.jpg", "Downloads/b.PNG", "x/node_modules/c.png", ".cache/d.png", "Music/s.mp3",
                "Documents/r.pdf", "Documents/t.odt", "Downloads/k.tar.zst", "Videos/v.mkv"):
        p = tmp_path / rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_text("x")
    os.utime(tmp_path / "Pictures/a.jpg", (time.time() - 100, time.time() - 100))
    names = lambda k: [e["name"] for e in fb.by_kind(k, root=str(tmp_path))["entries"]]
    assert names("pictures") == ["b.PNG", "a.jpg"]
    assert names("music") == ["s.mp3"] and names("videos") == ["v.mkv"]
    assert sorted(names("documents")) == ["r.pdf", "t.odt"] and names("archives") == ["k.tar.zst"]
