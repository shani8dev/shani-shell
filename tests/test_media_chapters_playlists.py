"""Media Player gaps closed: chapters read from the file, playlists of its own.

Chapters are read by ffprobe (-show_chapters, JSON) in Services/PlayQueue when
a video opens and exposed as [{ title, start, end }]; the window lists them and
jumps to one. Playlists are [{ name, paths }] kept as JSON in the shell's state
folder (media-playlists.json), with save/open/add/delete, shown on the Library
page. This file pins the wiring: the service owns the data, the window only
shows it, and the state reader sees both.
"""

import ast
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / "shani/Services/PlayQueue.qml").read_text()
WINDOW = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text()
LIBRARY = (ROOT / "shani/Modules/MediaPlayer/MusicLibraryView.qml").read_text()
SHELL = (ROOT / "shani/shell.qml").read_text()


# ---- chapters -------------------------------------------------------------


def test_chapters_read_by_ffprobe():
    # the service asks ffprobe for chapters in JSON when a video opens
    assert '"-show_chapters"' in QUEUE and '"-of"' in QUEUE and '"json"' in QUEUE
    assert "id: chapterProc" in QUEUE
    # exposed as [{ title, start, end }] with seconds as floats
    assert "property var chapters" in QUEUE
    assert "parseFloat(c.start_time)" in QUEUE and "parseFloat(c.end_time)" in QUEUE
    assert "start:" in QUEUE and "end:" in QUEUE and "title:" in QUEUE


def test_chapters_degrade_when_absent():
    # ffprobe missing, or a file with none: no throw, just an empty list
    assert "root.chapters = []" in QUEUE
    assert "JSON.parse(text)" in QUEUE and "catch" in QUEUE


def test_chapters_listed_and_jump_to_one_in_the_window():
    # a list, not just a count; a row jumps to its start
    assert "id: chapterList" in WINDOW
    assert "model: PlayQueue.chapters" in WINDOW
    assert "modelData.start * 1000" in WINDOW
    assert "PlayQueue.clock(chapterRow.modelData.start)" in WINDOW


# ---- playlists ------------------------------------------------------------


def test_playlists_are_a_json_file_in_the_state_dir():
    assert "property var playlists" in QUEUE
    assert 'Quickshell.statePath("media-playlists.json")' in QUEUE
    assert "id: playlistStore" in QUEUE


def test_playlist_actions():
    for fn in (
        "savePlaylist(",
        "saveQueueAs(",
        "openPlaylist(",
        "addToPlaylist(",
        "addPlayingTo(",
        "deletePlaylist(",
    ):
        assert f"function {fn}" in QUEUE, fn
    # the playing file is what gets added by default
    assert "root.current" in QUEUE
    # no duplicates on a re-add
    assert "indexOf(one) >= 0" in QUEUE


def test_playlists_on_the_library_page():
    # a Playlists tab beside albums/artists/songs/videos, with the actions
    assert '["playlists"' in LIBRARY
    assert "PlayQueue.playlists" in LIBRARY
    assert "PlayQueue.saveQueueAs(" in LIBRARY
    assert "PlayQueue.openPlaylist(" in LIBRARY
    assert "PlayQueue.addPlayingTo(" in LIBRARY
    assert "PlayQueue.deletePlaylist(" in LIBRARY


def test_state_and_ipc_expose_playlists_and_chapters():
    # the shell's state() reports both, for the suite and the CLI
    assert "mediaChapters: PlayQueue.chapters.length" in SHELL
    assert "mediaPlaylists: PlayQueue.playlists.map" in SHELL
    for fn in (
        "mediaPlaylistSave(",
        "mediaPlaylistOpen(",
        "mediaPlaylistAdd(",
        "mediaPlaylistDelete(",
    ):
        assert f"function {fn}" in SHELL, fn


# ---- the bridge is not needed, and says why -------------------------------
# Chapters are read by a direct ffprobe Process (the same way MusicLibrary,
# subFinder and siblings read files), and playlists are JSON in the state
# folder. A bridge would be more code for no gain, so none is added; the
# existing ffprobe call in PlayQueue is the chapters reader.


def test_no_new_bridge_was_added_for_chapters():
    # guard against a later well-meaning bridge duplicating the ffprobe call
    bridges = list((ROOT / "bridge").glob("*.py"))
    assert not any("chapter" in b.stem for b in bridges)


# ---- a real file: ffprobe chapters parse to { title, start, end } ----------


@pytest.mark.skipif(
    not (shutil.which("ffmpeg") and shutil.which("ffprobe")),
    reason="ffmpeg is not installed",
)
def test_ffprobe_chapters_parse_to_title_start_end(tmp_path):
    # a two-chapter file, as the service would read it
    base = tmp_path / "base.mp4"
    subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "testsrc=duration=10:size=320x240:rate=10",
            "-c:v",
            "libx264",
            "-preset",
            "ultrafast",
            str(base),
        ],
        check=True,
    )
    meta = tmp_path / "meta.txt"
    meta.write_text(
        ";FFMETADATA1\n"
        "[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=5000\ntitle=Opening\n\n"
        "[CHAPTER]\nTIMEBASE=1/1000\nSTART=5000\nEND=10000\ntitle=Main\n"
    )
    out = tmp_path / "withchap.mkv"
    subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-i",
            str(base),
            "-i",
            str(meta),
            "-map",
            "0",
            "-map_metadata",
            "1",
            "-codec",
            "copy",
            str(out),
        ],
        check=True,
    )
    raw = subprocess.run(
        ["ffprobe", "-v", "error", "-show_chapters", "-of", "json", "--", str(out)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    chapters = (json.loads(raw) or {}).get("chapters") or []
    # the same mapping the service does
    got = [
        {
            "title": (c.get("tags") or {}).get("title", ""),
            "start": float(c["start_time"]),
            "end": float(c["end_time"]),
        }
        for c in chapters
    ]
    assert [c["title"] for c in got] == ["Opening", "Main"]
    assert got[0]["start"] == 0.0 and got[0]["end"] == 5.0
    assert got[1]["start"] == 5.0 and got[1]["end"] == 10.0
