"""bridge/cleanup.py in a home made here: sizes are right, what is cleaned is
gone and nothing else is, the kept caches and anything that is not a cache
folder are refused, and old downloads go to the Trash, not away."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "bridge" / "cleanup.py"


def run(home, *args, ok=True):
    gio = home / "gio"
    # a stand-in for `gio trash`: records what it was asked, moves files into the Trash
    gio.write_text("#!/bin/sh\necho \"$@\" >> \"$HOME/gio-log\"\n"
                   "if [ \"$2\" = --empty ]; then rm -rf \"$HOME/.local/share/Trash/files\"/* \"$HOME/.local/share/Trash/info\"/*; exit 0; fi\n"
                   "shift 2; mkdir -p \"$HOME/.local/share/Trash/files\"; mv -- \"$@\" \"$HOME/.local/share/Trash/files/\"\n")
    gio.chmod(0o755)
    env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_")}
    env.update(HOME=str(home), SHANI_GIO=str(gio))
    r = subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True, env=env)
    assert (r.returncode == 0) == ok, r.stderr
    return json.loads(r.stdout) if ok else r


def make(path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)


def test_scan_and_clean(tmp_path):
    home = tmp_path
    make(home / ".cache/thumbnails/large/a.png", 1000)
    make(home / ".cache/some-app/blob", 5000)
    make(home / ".cache/shani-chronoa/model.gguf", 7000)
    make(home / ".local/share/Trash/files/old.txt", 300)
    make(home / "Downloads/ancient.zip", 2000)
    make(home / "Downloads/fresh.pdf", 100)
    long_ago = time.time() - 200 * 86400
    os.utime(home / "Downloads/ancient.zip", (long_ago, long_ago))

    got = run(home, "scan")
    assert got["thumbnails"]["size"] == 1000 and got["trash"] == {"size": 300, "count": 1}
    caches = {c["name"]: c for c in got["caches"]}
    assert caches["some-app"]["size"] == 5000 and caches["some-app"]["keep"] == ""
    assert "model" in caches["shani-chronoa"]["keep"] and caches["shani-chronoa"]["size"] == 7000
    assert got["downloads"]["count"] == 1 and got["downloads"]["items"] == ["ancient.zip"] and got["downloads"]["size"] == 2000

    run(home, "clean", "thumbnails")
    assert not (home / ".cache/thumbnails").exists()
    run(home, "clean", "cache", "some-app")
    assert not (home / ".cache/some-app").exists() and (home / ".cache/shani-chronoa/model.gguf").exists()
    # old downloads into the Trash, the new one stays
    run(home, "clean", "downloads")
    assert (home / ".local/share/Trash/files/ancient.zip").exists() and (home / "Downloads/fresh.pdf").exists()
    run(home, "clean", "trash")
    assert list((home / ".local/share/Trash/files").iterdir()) == []


def test_refuses_what_is_not_a_cache_folder(tmp_path):
    make(tmp_path / ".cache/shani-chronoa/model.gguf", 10)
    make(tmp_path / "Documents/keep.txt", 10)
    for name in ("../Documents", "/etc", "shani-chronoa", "..", "nope"):
        r = run(tmp_path, "clean", "cache", name, ok=False)
        assert r.returncode == 3
    assert (tmp_path / "Documents/keep.txt").exists() and (tmp_path / ".cache/shani-chronoa/model.gguf").exists()
