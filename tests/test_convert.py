"""bridge/convert.py on files made here: each kind into its formats, the new
file beside the old one under a free name, progress reported, the original
untouched, and what cannot be done refused with a reason."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[1] / "bridge" / "convert.py"
pytestmark = pytest.mark.skipif(not (shutil.which("ffmpeg") and shutil.which("ffprobe")), reason="ffmpeg is not installed")


def run(*args):
    r = subprocess.run([sys.executable, str(TOOL), *map(str, args)], capture_output=True, text=True, timeout=180)
    return r.returncode, [json.loads(l) for l in r.stdout.splitlines() if l.strip()]


@pytest.fixture
def media(tmp_path):
    v = tmp_path / "trip.webm"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=duration=3:size=320x240:rate=15", "-f", "lavfi",
                    "-i", "sine=frequency=440:duration=3", "-c:v", "libvpx", "-c:a", "libvorbis", str(v)], check=True)
    a = tmp_path / "song.wav"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=330:duration=2", str(a)], check=True)
    return v, a


def probe(path, entry):
    return subprocess.run(["ffprobe", "-v", "error", "-show_entries", entry, "-of", "default=nw=1:nk=1", str(path)],
                          capture_output=True, text=True).stdout.split()


def test_a_video_to_mp4_and_its_sound_to_mp3(media):
    video, _ = media
    before = video.read_bytes()
    code, out = run("run", video, "mp4", "small")
    assert code == 0, out
    done = Path(out[-1]["done"])
    assert done == video.with_suffix(".mp4") and "h264" in probe(done, "stream=codec_name")
    assert any(o.get("progress", 0) > 0 for o in out[:-1])
    assert video.read_bytes() == before                      # the original as it was
    code, out = run("run", video, "mp3")
    assert code == 0 and probe(Path(out[-1]["done"]), "stream=codec_name") == ["mp3"]


def test_never_written_over_and_nothing_half_made(media):
    _, song = media
    taken = song.with_suffix(".ogg")
    taken.write_text("mine")
    code, out = run("run", song, "ogg")
    assert code == 0 and Path(out[-1]["done"]).name == "song (2).ogg" and taken.read_text() == "mine"
    assert not list(song.parent.glob("*.part"))


def test_what_cannot_be_done_is_refused(media, tmp_path):
    video, song = media
    assert "cannot be made into mp4" in run("run", song, "mp4")[1][-1]["error"]
    note = tmp_path / "notes.txt"
    note.write_text("x")
    assert "not a video" in run("run", note, "mp3")[1][-1]["error"]
    assert json.loads(subprocess.run([sys.executable, str(TOOL), "formats", str(video)], capture_output=True, text=True).stdout)["kind"] == "video"


@pytest.mark.skipif(not (shutil.which("magick") or shutil.which("convert")), reason="ImageMagick is not installed")
def test_a_picture_to_webp(tmp_path):
    pic = tmp_path / "photo.png"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=64x64", "-frames:v", "1", str(pic)], check=True)
    code, out = run("run", pic, "webp")
    assert code == 0 and Path(out[-1]["done"]).read_bytes()[8:12] == b"WEBP"
