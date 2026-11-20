"""The Live TV M3U reader: Hypnotix-style channels for shani's Media Player."""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "bridge" / "live-tv.py"
spec = importlib.util.spec_from_file_location("live_tv", SOURCE)
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)

PLAYLIST = """#EXTM3U
#EXTINF:-1 tvg-id="news18" tvg-logo="http://logo/news.png" group-title="News",News 18
http://stream/news
#EXTINF:-1 group-title="Movies",A Movie
http://stream/movie
#EXTGRP:Sports
http://stream/sports
# a comment
http://stream/bare
"""


def test_parse_reads_extinf_attributes_and_extgrp():
    got = live.parse(PLAYLIST)
    assert [c["name"] for c in got] == [
        "News 18",
        "A Movie",
        "sports",
        "bare",
    ]
    assert got[0]["id"] == "news18"
    assert got[0]["logo"] == "http://logo/news.png"
    assert got[0]["group"] == "News"
    assert got[2]["group"] == "Sports"
    assert got[3]["url"] == "http://stream/bare"


def test_a_playlist_with_no_channels_is_an_honest_error(tmp_path):
    p = tmp_path / "empty.m3u"
    p.write_text("#EXTM3U\n# nothing here\n")
    out = subprocess.run(
        [sys.executable, str(SOURCE), str(p)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "error" in json.loads(out)


def test_a_missing_file_does_not_crash(tmp_path):
    out = subprocess.run(
        [sys.executable, str(SOURCE), str(tmp_path / "gone.m3u")],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "error" in json.loads(out)


def test_live_tv_is_wired_into_the_media_player():
    window = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text()
    assert 'Tr.t("Live TV")' in window
    assert "LiveTvView {" in window
    assert 'win.page === "live"' in window
    shell = (ROOT / "shani/shell.qml").read_text()
    assert "function liveTvOpen" in shell
    assert "function liveTvLoad" in shell
    assert "liveTvChannels:" in shell
    settings = (ROOT / "shani/Common/Settings.qml").read_text()
    assert "property string liveTvSource" in settings
    session = (ROOT / "dev/session.sh").read_text()
    assert "SHANI_LIVETV_TOOL=/work/bridge/live-tv.py" in session


def test_free_picks_are_bundled_and_playable():
    out = subprocess.run([sys.executable, str(SOURCE), "defaults"], capture_output=True, text=True, check=True).stdout
    channels = json.loads(out)
    names = [c["name"] for c in channels]
    groups = {c["group"] for c in channels}
    assert len(channels) >= 100
    assert "NDTV India" in names and "DW" in names
    assert {"India", "News", "UK", "USA"} <= groups
    assert all(c["url"].startswith("https://") for c in channels)


def test_free_picks_are_wired_into_both_pages():
    tv = (ROOT / "shani/Services/LiveTv.qml").read_text()
    assert "function loadDefaults" in tv
    radio = (ROOT / "shani/Services/Radio.qml").read_text()
    assert '"featured"' in radio and "SomaFM Groove Salad" in radio and "BIG 92.7 FM" in radio
    assert radio.count('uuid: ""') >= 50
    view = (ROOT / "shani/Modules/MediaPlayer/RadioView.qml").read_text()
    assert 'Tr.t("Free picks")' in view


def test_extinf_without_a_comma_falls_back_to_tvg_name():
    got = live.parse('#EXTM3U\n#EXTINF:-1 tvg-name="Fallback" group-title="News"\nhttp://x/live\n')
    assert got[0]["name"] == "Fallback"


def test_media_player_has_keys_for_radio_and_live_tv():
    w = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text()
    assert "Qt.Key_R" in w and "Qt.Key_T" in w
    assert 'win.page = "live"' in w
