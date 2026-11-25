"""Static hooks for "Show in Files" across the shell's file viewers.

QML is compiled by the render harness, so these read the surfaces as text. Each
viewer owns a local reveal(path) helper built on the file manager's existing
show(dir) + select(path) API, with a named, keyboard reachable control. The pure
logic tests mirror that helper's path split, including the guard that keeps
http/rtsp addresses out of the file manager.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


SURFACES = {
    "shani/Modules/Viewer/Viewer.qml": "Qt.Key_L && (e.modifiers & Qt.ControlModifier)",
    "shani/Modules/Photos/PhotosWindow.qml": "event.key === Qt.Key_R",
    "shani/Modules/PdfReader/PdfReader.qml": "Qt.Key_L && (e.modifiers & Qt.ControlModifier)",
    "shani/Modules/MediaPlayer/MediaPlayerWindow.qml": "Qt.Key_L && (e.modifiers & Qt.ControlModifier)",
    "shani/Modules/Archives/ArchivesWindow.qml": "(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_L",
}
LABEL = r'Tr\.t\("(?:Show|Reveal) in Files'


@pytest.mark.parametrize("rel,shortcut", SURFACES.items())
def test_surface_has_named_keyboard_reveal_hook(rel, shortcut):
    src = read(rel)
    assert "function reveal(" in src, rel
    assert 'startsWith("/")' in src, rel  # streams have no folder on disk
    assert "Files.show(" in src and "Files.select(" in src, rel
    assert re.search(LABEL, src), rel  # tip/text is the control's AT-SPI name
    assert shortcut in src, rel  # keyboard users get the same action


def test_media_player_does_not_reveal_streams():
    src = read("shani/Modules/MediaPlayer/MediaPlayerWindow.qml")
    assert "PlayQueue.isStream" in src
    assert 'const p = PlayQueue.isStream ? "" :' in src


# ---- the pure path logic ---------------------------------------------------


def reveal_target(path, stream=False):
    """The (folder, file) the local helpers target, or None for no local file."""
    p = "" if stream else str(path or "")
    if not p.startswith("/"):  # a stream URL or a relative name
        return None
    at = p.rfind("/")
    directory = "/" if at == 0 else p[:at]
    if not directory:
        return None
    return directory, p[at + 1 :]


@pytest.mark.parametrize(
    "path,expected",
    [
        ("/home/me/Pictures/a b.jpg", ("/home/me/Pictures", "a b.jpg")),
        ("/a.jpg", ("/", "a.jpg")),  # a file in the root folder
        ("/home/me/movie.mkv", ("/home/me", "movie.mkv")),
        ("/home/me/", ("/home/me", "")),
        ("", None),
        (None, None),
        ("a.jpg", None),  # relative: no folder to open
    ],
)
def test_path_split(path, expected):
    assert reveal_target(path) == expected


@pytest.mark.parametrize(
    "url",
    [
        "http://example.com/live.m3u8",
        "https://example.com/song.mp3",
        "rtsp://camera.local/stream",
        "rtmp://example.com/live",
        "udp://239.0.0.1:1234",
        "sftp://host/video.mp4",
        "file:///home/me/video.mp4",
    ],
)
def test_streams_are_not_revealed(url):
    assert reveal_target(url) is None
    assert reveal_target(url, stream=True) is None


def test_the_qml_guard_matches_the_pure_logic():
    # keep the mirror honest: every viewer must reject a non-local path before
    # it asks the file manager to show anything
    for rel in SURFACES:
        assert 'if (!p.startsWith("/")) return;' in read(rel), rel
