"""One wiring test per Podcasts cross-link.

There is no QML runtime here, so the logic tests extract the verbatim
`function ... { ... }` bodies from the QML and run them in node against stubbed
singletons — the same trick as test_mail_feeds_wave5.py. Static assertions pin
the UI strings and the service calls the views must make.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
FEEDS_WINDOW = ROOT / "shani/Modules/Feeds/FeedsWindow.qml"
PODCAST_SERVICE = ROOT / "shani/Services/Podcasts.qml"
PODCAST_WINDOW = ROOT / "shani/Modules/MediaPlayer/PodcastWindow.qml"

NODE = shutil.which("node")
needs_node = pytest.mark.skipif(NODE is None, reason="node runs the verbatim QML JS")


def src(path):
    return path.read_text(encoding="utf-8")


def fn(source, name):
    """The verbatim `function name(...) { ... }` block, braces matched."""
    m = re.search(r"function\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", source)
    assert m, f"no function {name}() in the QML source"
    depth = 0
    for k in range(m.end() - 1, len(source)):
        if source[k] == "{":
            depth += 1
        elif source[k] == "}":
            depth -= 1
            if depth == 0:
                return source[m.start() : k + 1]
    raise AssertionError(f"unbalanced braces in {name}()")


def js(code):
    run = subprocess.run([NODE, "-e", code], capture_output=True, text=True, check=True)
    return json.loads(run.stdout)


# ---- 1. Feeds: audio rows hand the feed to Podcasts -------------------------


def test_feeds_audio_row_offers_listen_as_podcast_and_uses_the_ui_open_path():
    s = src(FEEDS_WINDOW)
    assert "property var audioFeeds: []" in s
    assert "function onItemsChanged() { win.rememberAudio(); }" in s
    assert "i.enclosure && i.enclosure.url" in s  # what makes a row an audio feed
    assert 'tip: Tr.t("Listen as podcast")' in s
    assert 'accessibleName: Tr.t("Listen as podcast")' in s
    body = fn(s, "listenAsPodcast")
    assert "Podcasts.listenToFeed(url)" in body
    assert "Ui.closeAll()" in body and "Ui.podcasts = true" in body


@needs_node
def test_feeds_handoff_is_scoped_to_audio_feeds_and_opens_podcasts():
    s = src(FEEDS_WINDOW)
    out = js(
        f"""
var called = [];
var Podcasts = {{ listenToFeed: u => called.push(["feed", u]) }};
var Ui = {{ closeAll: () => called.push(["close"]), podcasts: false }};
var win = {{ audioFeeds: ["a"] }};
{fn(s, "hasAudio")}
{fn(s, "listenAsPodcast")}
var audio = [hasAudio("a"), hasAudio("b")];
listenAsPodcast("");
listenAsPodcast("a");
console.log(JSON.stringify([audio, called, Ui.podcasts]));
"""
    )
    assert out == [[True, False], [["feed", "a"], ["close"]], True]


# ---- 2. PodcastWindow: an episode opens in the Media Player ----------------


def test_episode_open_in_media_player_uses_the_service_handoff():
    w = src(PODCAST_WINDOW)
    s = src(PODCAST_SERVICE)
    assert 'text: Tr.t("Open in Media Player")' in w
    assert "onClicked: Podcasts.play(modelData.url, modelData.id)" in w
    # the service already hands the enclosure to PlayQueue — verify, don't redo
    assert "const enc = row && row.enclosure && row.enclosure.url;" in s
    assert "PlayQueue.validStreamUrl(enc)" in s
    assert "PlayQueue.playStream(enc" in s and "PlayQueue.open(enc)" in s


@needs_node
def test_podcast_play_hands_the_enclosure_url_to_playqueue():
    s = src(PODCAST_SERVICE)
    out = js(
        f"""
var played = [], saved = 0;
var Tr = {{ t: x => x }};
var PlayQueue = {{
  validStreamUrl: u => /^https?:/.test(u),
  playStream: (u, t) => played.push(["stream", u, t]),
  open: u => played.push(["open", u])
}};
var root = {{
  episodes: [
    {{ url: "u", id: "1", title: "Ep 1", enclosure: {{ url: "https://cdn/e1.mp3" }} }},
    {{ url: "u", id: "2", title: "Ep 2", enclosure: {{}} }}
  ],
  note: "old", lastFeed: "", lastEpisode: "",
  currentFeed: "", currentEpisode: "", saveState: () => saved++
}};
{fn(s, "play")}
play("u", "1");
play("u", "2");
console.log(JSON.stringify([played, root.note, root.lastFeed, root.lastEpisode, saved]));
"""
    )
    assert out == [
        [["stream", "https://cdn/e1.mp3", "Ep 1"]],
        "That episode has no audio to play",
        "u",
        "u|1",
        1,
    ]


# ---- 3. Podcasts service: last feed / episode persist and restore ----------


def test_podcasts_service_persists_restores_and_exposes_an_error_note():
    s = src(PODCAST_SERVICE)
    assert 'Quickshell.statePath("podcast-state.json")' in s
    assert "if (d.lastFeed) root.lastFeed = d.lastFeed;" in s
    assert "if (d.lastEpisode) root.lastEpisode = d.lastEpisode;" in s
    assert 'property string note: ""' in s
    assert 'Tr.t("Could not add that feed")' in s
    assert "Component.onCompleted: Podcasts.restore()" in src(PODCAST_WINDOW)


@needs_node
def test_podcasts_restore_and_listen_to_feed_write_the_state_file():
    s = src(PODCAST_SERVICE)
    out = js(
        f"""
var writes = [], added = [];
var stateStore = {{ setText: x => writes.push(x) }};
var Tr = {{ t: x => x }};
var root = {{
  favourites: ["f"], lastPlayed: {{ k: 3 }},
  lastFeed: "feed2", lastEpisode: "feed2|e7",
  currentFeed: "", currentEpisode: "", note: "",
  addFeed: u => added.push(u)
}};
{fn(s, "saveState")}
{fn(s, "restore")}
{fn(s, "listenToFeed")}
root.saveState = saveState;
restore();
var restored = [root.currentFeed, root.currentEpisode];
listenToFeed("  feed3  ");
listenToFeed("");
console.log(JSON.stringify([restored, root.lastFeed, root.note, added, JSON.parse(writes[0])]));
"""
    )
    assert out == [
        ["feed2", "feed2|e7"],
        "feed3",
        "No feed address to listen to",
        ["feed3"],
        {
            "favourites": ["f"],
            "lastPlayed": {"k": 3},
            "lastFeed": "feed3",
            "lastEpisode": "feed2|e7",
        },
    ]


# ---- 4. PodcastWindow: favourites and downloaded filters -------------------


def test_podcast_window_has_favourites_and_downloaded_filters():
    w = src(PODCAST_WINDOW)
    assert 'property string filter: "all"' in w
    for label in ("All", "Favourites", "Downloaded"):
        assert f'text: Tr.t("{label}")' in w
    assert "model: win.shownEpisodes()" in w
    assert "visible: win.shownEpisodes().length === 0" in w


@needs_node
def test_podcast_filters_show_only_favourites_or_finished_downloads():
    w = src(PODCAST_WINDOW)
    out = js(
        f"""
var Podcasts = {{
  episodes: [
    {{ url: "u", id: "1", enclosure: {{ url: "e1" }} }},
    {{ url: "u", id: "2", enclosure: {{ url: "e2" }} }},
    {{ url: "v", id: "3" }}
  ],
  favourites: ["u|2"],
  downloads: [{{ url: "e1", state: "done" }}, {{ url: "e2", state: "failed" }}]
}};
var win = {{ filter: "all" }};
{fn(w, "shownEpisodes")}
var out = {{}};
["all", "favourites", "downloaded"].forEach(function(f) {{
  win.filter = f;
  out[f] = shownEpisodes().map(r => r.id);
}});
console.log(JSON.stringify(out));
"""
    )
    assert out == {"all": ["1", "2", "3"], "favourites": ["2"], "downloaded": ["1"]}


# ---- 5. PodcastWindow: empty state offers Add a feed -----------------------


def test_podcast_empty_state_has_an_add_feed_action():
    w = src(PODCAST_WINDOW)
    block = w[w.index("EmptyState {") : w.index("EmptyState {") + 700]
    assert "visible: win.shownEpisodes().length === 0" in block
    assert 'actionText: Tr.t("Add a feed")' in block
    assert "onAction: feedField.forceActiveFocus()" in block
