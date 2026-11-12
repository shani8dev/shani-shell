"""bridge/music-library.py on songs made here with ffmpeg: tags read, the
usual folder layout used when there are none, covers found, and a second scan
reads nothing again."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[1] / "bridge" / "music-library.py"
pytestmark = pytest.mark.skipif(not (shutil.which("ffmpeg") and shutil.which("ffprobe")), reason="ffmpeg is not installed")


def song(path, seconds=2, **tags):
    path.parent.mkdir(parents=True, exist_ok=True)
    meta = [a for k, v in tags.items() for a in ("-metadata", f"{k}={v}")]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}", *meta, "-c:a", "libvorbis", str(path)], check=True)


def scan(tmp, root):
    env = dict(os.environ, XDG_CACHE_HOME=str(tmp / "cache"))
    out = subprocess.run([sys.executable, str(TOOL), "scan", str(root)], capture_output=True, text=True, env=env, check=True).stdout
    return json.loads(out)


def test_tags_layout_covers_and_the_cache(tmp_path):
    music = tmp_path / "Music"
    song(music / "x" / "b.ogg", title="Second", artist="Band", album="Record", track="2")
    song(music / "x" / "a.ogg", title="First", artist="Band", album="Record", track="1/10", date="2019")
    (music / "x" / "cover.jpg").write_bytes(b"\xff\xd8\xff")
    song(music / "Old Artist" / "Old Album" / "03 - Untagged Song.ogg")
    (music / ".hidden").mkdir()
    song(music / ".hidden" / "skip.ogg")
    (music / "notes.txt").write_text("not a song")

    got = scan(tmp_path, music)
    assert got["scanned"] == 3 and got["read"] == 3
    by = {s["title"]: s for s in got["songs"]}
    assert set(by) == {"First", "Second", "Untagged Song"}
    first = by["First"]
    assert (first["artist"], first["album"], first["track"], first["year"]) == ("Band", "Record", 1, 2019)
    assert first["cover"] == str(music / "x" / "cover.jpg") and 1.5 < first["duration"] < 2.5
    loose = by["Untagged Song"]
    assert (loose["artist"], loose["album"], loose["track"], loose["cover"]) == ("Old Artist", "Old Album", 3, "")
    # an album in track order
    assert [s["title"] for s in got["songs"] if s["album"] == "Record"] == ["First", "Second"]

    again = scan(tmp_path, music)
    assert again["read"] == 0 and len(again["songs"]) == 3
    song(music / "x" / "b.ogg", seconds=3, title="Second (live)", artist="Band", album="Record", track="2")
    assert scan(tmp_path, music)["read"] == 1


def test_videos_newest_first_with_a_thumbnail_and_the_folder(tmp_path):
    videos = tmp_path / "Videos"
    (videos / "Series").mkdir(parents=True)
    for name, t in (("Series/ep_01.webm", 100), ("Series/ep_02.webm", 200), ("holiday.webm", 300)):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=duration=3:size=320x240:rate=10",
                        "-c:v", "libvpx", str(videos / name)], check=True)
        os.utime(videos / name, (t, t))
    env = dict(os.environ, XDG_CACHE_HOME=str(tmp_path / "cache"))
    got = json.loads(subprocess.run([sys.executable, str(TOOL), "videos", str(videos)], capture_output=True, text=True, env=env, check=True).stdout)
    assert [v["title"] for v in got["videos"]] == ["holiday", "ep 02", "ep 01"]
    assert [v["folder"] for v in got["videos"]] == ["", "Series", "Series"]
    assert all(2.5 < v["duration"] < 3.5 and Path(v["thumb"]).stat().st_size > 0 for v in got["videos"])
    again = json.loads(subprocess.run([sys.executable, str(TOOL), "videos", str(videos)], capture_output=True, text=True, env=env, check=True).stdout)
    assert again["read"] == 0
