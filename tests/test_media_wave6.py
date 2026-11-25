"""Wave 6: network streams, .m3u playlists and a persisted recent-media list.

The stream allowlist and the recent list's cap/dedupe are plain JS in the
service, so they are run through node instead of guessed at from the source.
The .m3u reader/writer is a real stdlib bridge, so it is exercised as a
subprocess against temp files as well as through its Python functions.
"""

import ast
import importlib.util
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / "shani/Services/PlayQueue.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text(
    encoding="utf-8"
)
INFO = (ROOT / "shani/Services/MediaInfo.qml").read_text(encoding="utf-8")
BRIDGE = ROOT / "bridge/playlist.py"
NODE = shutil.which("node") or shutil.which("nodejs")

_spec = importlib.util.spec_from_file_location("shani_playlist", BRIDGE)
pl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pl)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


# ---- static wiring ---------------------------------------------------------


def test_stream_allowlist_lives_in_the_service():
    assert "readonly property var streamSchemes:" in QUEUE
    assert "function validStreamUrl(u)" in QUEUE
    assert "readonly property bool isStream: validStreamUrl(current)" in QUEUE
    # the window asks the service; it does not keep a second allowlist
    assert "if (PlayQueue.validStreamUrl(url))" in WINDOW
    assert "root.validStreamUrl(path)" in QUEUE  # playRecent and remember
    assert "PlayQueue.isStream" in INFO  # no second stream probe


def test_stream_field_accepts_more_than_http():
    assert "id: streamField" in WINDOW
    assert 'mode: "url"' in WINDOW
    assert 'label: Tr.t("Stream address")' in WINDOW
    assert 'Tr.t("Enter an http, rtsp or rtmp address")' in WINDOW
    assert "network-workgroup" in WINDOW


def test_m3u_save_and_load_are_wired_to_the_picker():
    assert "SHANI_PLAYLIST_TOOL" in QUEUE
    assert '"python3", root.playlistTool, "write"' in QUEUE
    assert '"python3", root.playlistTool, "read"' in QUEUE
    assert "function saveQueueM3u(path)" in QUEUE
    assert "function loadPlaylistM3u(path)" in QUEUE
    assert "root.queue.map(" in QUEUE  # the queue is the playlist
    assert 'x.startsWith("/") || root.validStreamUrl(x)' in QUEUE  # filter on load
    assert "PlayQueue.saveQueueM3u(paths[0])" in WINDOW
    assert "PlayQueue.loadPlaylistM3u(paths[0])" in WINDOW
    assert 'mode: "save"' in WINDOW and 'mode: "open"' in WINDOW
    assert 'filters: ["m3u"]' in WINDOW and '["m3u", "m3u8"]' in WINDOW
    assert "PlayQueue.playlistNote" in WINDOW  # result is visible


def test_recent_media_is_persisted_and_clearable():
    assert "Settings.path" in QUEUE  # sibling of the settings file
    assert '"/media-recent.json"' in QUEUE
    assert "atomicWrites: true" in QUEUE
    assert "JsonAdapter { id: recentPrefs; property list<string> items: [] }" in QUEUE
    assert "JSON.parse(s)" in QUEUE and "JSON.stringify(x)" in QUEUE
    assert "readonly property int recentCap" in QUEUE
    assert "function recentAdd(items, entry)" in QUEUE
    assert "function rememberRecent(path, title)" in QUEUE
    assert "function clearRecent()" in QUEUE
    assert "root.rememberRecent(current" in QUEUE  # recorded when a track starts
    # shown on the Library tab, with a clear action and names for the reader
    assert 'win.page === "library" || win.page === "playing"' in WINDOW
    assert "model: PlayQueue.recentRows" in WINDOW
    assert "PlayQueue.clearRecent()" in WINDOW
    assert 'Accessible.name: Tr.t("Clear recent media")' in WINDOW
    assert "Accessible.role: Accessible.ListItem" in WINDOW
    assert "PlayQueue.playRecent(recentRow.modelData.path)" in WINDOW


def test_bridge_needs_no_new_dependency():
    tree = ast.parse(BRIDGE.read_text(encoding="utf-8"))
    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.add(node.module.split(".")[0])
    assert imports <= {"__future__", "json", "os", "re", "sys"}


# ---- the real bridge -------------------------------------------------------


def test_parse_extm3u_reads_titles_and_paths():
    text = "#EXTM3U\n#EXTINF:-1,Artist - Song\n/music/a.mp3\nhttps://x/s.m3u8\n"
    got = pl.parse_m3u(text)
    assert got["count"] == 2
    assert got["entries"][0] == {"path": "/music/a.mp3", "title": "Artist - Song"}
    assert got["entries"][1] == {"path": "https://x/s.m3u8", "title": ""}


def test_render_m3u_is_standard_and_drops_bad_entries():
    text = pl.render_m3u(
        [
            {"path": "/videos/film.mkv", "title": "A film"},
            {"path": "rtsp://cam/live", "title": ""},
            {"path": "../nope", "title": "relative"},
            {"path": "/bad\nname.mp3", "title": "control"},
        ]
    )
    lines = text.splitlines()
    assert lines[0] == "#EXTM3U"
    assert lines[1] == "#EXTINF:-1,A film" and lines[2] == "/videos/film.mkv"
    assert lines[3] == "#EXTINF:-1,live" and lines[4] == "rtsp://cam/live"
    assert "../nope" not in text and "bad" not in text
    assert pl.parse_m3u(text)["count"] == 2


def test_write_then_read_roundtrip_with_temp_files(tmp_path):
    out = tmp_path / "queue.m3u"
    entries = [
        {"path": str(tmp_path / "a.mp3"), "title": "First"},
        {"path": "https://example.test/radio", "title": "A station"},
    ]
    write = subprocess.run(
        [
            sys.executable,
            str(BRIDGE),
            "write",
            str(out),
            json.dumps({"entries": entries}),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert write.returncode == 0, write.stderr
    assert json.loads(write.stdout)["count"] == 2
    assert out.read_text(encoding="utf-8").startswith("#EXTM3U\n")

    read_back = subprocess.run(
        [sys.executable, str(BRIDGE), "read", str(out)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert read_back.returncode == 0, read_back.stderr
    got = json.loads(read_back.stdout)
    assert [e["path"] for e in got["entries"]] == [e["path"] for e in entries]
    assert [e["title"] for e in got["entries"]] == [e["title"] for e in entries]


def test_relative_entry_in_a_file_is_read_next_to_that_file(tmp_path):
    p = tmp_path / "songs.m3u"
    p.write_text("#EXTM3U\n#EXTINF:-1,Local\nsongs/one.mp3\n", encoding="utf-8")
    got = pl.parse_m3u(p.read_text(encoding="utf-8"), str(p.parent))
    assert got["entries"][0]["path"] == str(tmp_path / "songs/one.mp3")


def test_bridge_rejects_bad_targets_and_reports_missing_files(tmp_path):
    bad = subprocess.run(
        [sys.executable, str(BRIDGE), "write", "https://example.test/x.m3u", "[]"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert bad.returncode != 0 and "error" in json.loads(bad.stdout)

    missing = subprocess.run(
        [sys.executable, str(BRIDGE), "read", str(tmp_path / "gone.m3u")],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert missing.returncode != 0 and "error" in json.loads(missing.stdout)


# ---- the pure JS logic -----------------------------------------------------


def function_source(name: str, text: str) -> str:
    """One function verbatim, braces matched so nested objects are kept."""
    m = re.search(r"function " + name + r"\([^)]*\) \{", text)
    assert m, name
    start = text.index("{", m.start())
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[m.start() : i + 1]
    raise AssertionError("unbalanced function " + name)


def qml_constant(name: str, pattern: str):
    m = re.search(pattern, QUEUE)
    assert m, name
    return json.loads(m.group(1))


def run_node(js: str, expression: str):
    out = subprocess.run(
        [NODE, "-e", js + "\nconsole.log(JSON.stringify(" + expression + "));\n"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


def service_globals() -> str:
    schemes = qml_constant(
        "streamSchemes", r"readonly property var streamSchemes: (\[[^\]]*\])"
    )
    cap = qml_constant("recentCap", r"readonly property int recentCap: (\d+)")
    return (
        f"const root = {{ streamSchemes: {json.dumps(schemes)}, recentCap: {cap} }};\n"
    )


@pytest.mark.skipif(NODE is None, reason="node is not installed")
@pytest.mark.parametrize(
    "url,want",
    [
        ("https://example.test/a.m3u8", True),
        ("http://example.test/radio", True),
        ("rtsp://192.168.1.4/cam", True),
        ("rtmp://live.test/app/stream", True),
        ("srt://host:1234", True),
        ("UDP://host:1234", True),  # the scheme match is case-insensitive
        ("mms://host/stream", True),
        ("file:///etc/passwd", False),  # a local path is not a URL to open
        ("javascript:alert(1)", False),
        ("ssh://host/file", False),
        ("http:/one-slash", False),
        ("not a url", False),
        ("", False),
    ],
)
def test_valid_stream_url_allowlist(url, want):
    js = service_globals() + function_source("validStreamUrl", QUEUE) + "\n"
    assert run_node(js, f"validStreamUrl({json.dumps(url)})") is want


@pytest.mark.skipif(NODE is None, reason="node is not installed")
def test_recent_add_dedupes_moves_to_front_and_caps():
    js = service_globals() + function_source("recentAdd", QUEUE) + "\n"
    old = [
        {"path": "/old/" + str(i), "title": "old", "at": i} for i in range(24, -1, -1)
    ]
    got = run_node(
        js,
        "recentAdd(" + json.dumps(old) + ", { path: '/old/0', title: 'now', at: 99 })",
    )
    assert len(got) == 20
    assert got[0] == {"path": "/old/0", "title": "now", "at": 99}
    assert len([x for x in got if x["path"] == "/old/0"]) == 1
    assert [x["path"] for x in got][1] == "/old/24"  # the rest stay newest first
    assert run_node(js, "recentAdd([], {})") == []
