"""Static checks for the three missing-app files and the Podcasts window wiring.

QML is compiled by the render harness, so these read the files as text — no QML
runtime is needed. Each file gets one test: the service must own the data and
the bridge calls, each window must read and write the services it wraps, and
the new Podcast window must be a registered AppWindow that drives Podcasts.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


PODCASTS = read("shani/Services/Podcasts.qml")
DICTIONARY = read("shani/Modules/Dictionary.qml")
SCHEDULED = read("shani/Modules/ScheduledTasksWindow.qml")
PODCAST_WINDOW = read("shani/Modules/MediaPlayer/PodcastWindow.qml")


def test_podcasts_service_owns_feeds_playback_and_downloads():
    assert "pragma Singleton" in PODCASTS
    assert "Singleton {" in PODCASTS
    assert 'Quickshell.env("SHANI_FEEDS_TOOL")' in PODCASTS
    assert 'Quickshell.statePath("podcast-state.json")' in PODCASTS
    assert "function toggleFavourite(url, id)" in PODCASTS
    assert "function lastFor(url, id)" in PODCASTS
    assert "function run(what, args)" in PODCASTS
    assert "root.pending = { what: what, args: args };" in PODCASTS
    assert "function episodesFor(url)" in PODCASTS
    assert 'root.sortOrder === "newest" ? list.reverse() : list;' in PODCASTS
    assert "PlayQueue.validStreamUrl(enc)" in PODCASTS
    assert "PlayQueue.playStream(enc" in PODCASTS
    assert "PlayQueue.open(enc)" in PODCASTS
    assert '"curl", "-fL", "-o"' in PODCASTS
    assert 'root.run("list", []); }' in PODCASTS


def test_dictionary_is_an_offline_window_over_its_bundled_entries():
    assert "AppWindow {" in DICTIONARY
    assert 'appName: "Dictionary"' in DICTIONARY
    assert "visible: Ui.dictionary" in DICTIONARY
    assert "readonly property var entries: [" in DICTIONARY
    for field in ("definitions:", "synonyms:", "antonyms:"):
        assert field in DICTIONARY
    assert "readonly property var results: win.entries.filter" in DICTIONARY
    assert "win.history = win.history.slice(0, 20);" in DICTIONARY
    assert "function recall(w)" in DICTIONARY
    assert "Quickshell.clipboardText" in DICTIONARY
    assert "Keys.onEscapePressed: win.requestClose()" in DICTIONARY
    assert 'Tr.t("Clear"); kind: "plain"; onClicked: win.history = []' in DICTIONARY


def test_scheduled_tasks_window_reads_and_writes_the_services():
    assert "AppWindow {" in SCHEDULED
    assert 'appName: Tr.t("Scheduled tasks")' in SCHEDULED
    assert "visible: Ui.scheduled" in SCHEDULED
    assert "onGone: Ui.scheduled = false" in SCHEDULED
    assert "readonly property var rules: Automations.rules" in SCHEDULED
    assert "readonly property var fired: Automations.fired" in SCHEDULED
    assert "readonly property var hooks: Settings.data.hooks || {}" in SCHEDULED
    assert "function setRuleOn(i, on)" in SCHEDULED
    assert "Automations.prime();" in SCHEDULED
    assert "Automations.rulesChanged();" in SCHEDULED
    assert "function removeRule(i)" in SCHEDULED
    assert "function addRule()" in SCHEDULED
    assert 'if (win.is === "")' in SCHEDULED
    assert (
        '(win.then === "run" || win.then === "volume") && win.arg === ""' in SCHEDULED
    )
    assert "Settings.data.hooks = h" in SCHEDULED
    assert "model: win.fired" in SCHEDULED


def test_podcast_window_is_registered_and_drives_the_podcasts_service():
    assert "AppWindow {" in PODCAST_WINDOW
    assert 'appName: "Podcasts"' in PODCAST_WINDOW  # AppWindow self-registers by title
    assert "import qs.Services" in PODCAST_WINDOW
    assert "Podcasts.episodes" in PODCAST_WINDOW
    assert "Podcasts.error || Podcasts.note" in PODCAST_WINDOW
    assert "Podcasts.addFeed(" in PODCAST_WINDOW
    assert "Podcasts.searchFeeds(" in PODCAST_WINDOW
    assert "Podcasts.play(modelData.url, modelData.id)" in PODCAST_WINDOW
    assert "Podcasts.toggleFavourite(" in PODCAST_WINDOW
    assert "Podcasts.download(" in PODCAST_WINDOW
