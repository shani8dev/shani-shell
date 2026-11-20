"""bridge/dupes.py: duplicates only when every byte is the same (a file the same
size and start but a different end is not one), oldest first, hard links and
empty files not counted, hidden folders not looked in; the biggest files."""
import importlib.util
import os
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location("dupes", Path(__file__).resolve().parent.parent / "bridge" / "dupes.py")
dupes = importlib.util.module_from_spec(spec); spec.loader.exec_module(dupes)


def test_duplicates(tmp_path):
    big = os.urandom(200_000)
    (tmp_path / "a").mkdir(); (tmp_path / "b").mkdir(); (tmp_path / ".app").mkdir()
    (tmp_path / "a" / "movie.mp4").write_bytes(big)
    (tmp_path / "b" / "movie copy.mp4").write_bytes(big)
    (tmp_path / "b" / "nearly.mp4").write_bytes(big[:-1] + bytes([big[-1] ^ 1]))   # same start, other end
    (tmp_path / ".app" / "cache.mp4").write_bytes(big)                               # hidden: not looked in
    os.link(tmp_path / "a" / "movie.mp4", tmp_path / "a" / "hardlink.mp4")           # the same file, not a copy
    (tmp_path / "x.txt").write_text("hi"); (tmp_path / "y.txt").write_text("hi")
    (tmp_path / "e1").write_text(""); (tmp_path / "e2").write_text("")
    old = time.time() - 1000
    os.utime(tmp_path / "b" / "movie copy.mp4", (old, old))
    g = dupes.duplicates(str(tmp_path))
    assert g[0] == {"size": 200_000, "paths": [str(tmp_path / "b" / "movie copy.mp4"), str(tmp_path / "a" / "movie.mp4")]} \
        or g[0]["paths"][0] == str(tmp_path / "b" / "movie copy.mp4") and len(g[0]["paths"]) == 2
    assert sorted(g[1]["paths"]) == [str(tmp_path / "x.txt"), str(tmp_path / "y.txt")]
    assert len(g) == 2


def test_biggest(tmp_path):
    for i, n in enumerate((10, 3000, 500)):
        (tmp_path / f"f{i}").write_bytes(b"x" * n)
    assert [Path(e["path"]).name for e in dupes.biggest(str(tmp_path), 2)] == ["f1", "f2"]
