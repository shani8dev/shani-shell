"""Static checks: the original service singletons follow the run/finished +
busy/note/error contract the newer singletons (Irc/Health/Vpn/CloudSync/
Podcasts) already use.

There is no QML runtime in pytest, so these read the shipped source. Each
test guards one concrete part of the contract. All checks are additive: no
existing property, function signature or emitted string may be dropped.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def block(text, start):
    """The `{ … }` body that follows a marker, by brace matching."""
    i = text.index("{", text.index(start))
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1 : j]
    raise AssertionError("unbalanced block after " + start)


SERVICES = {
    name: source("shani/Services/%s.qml" % name)
    for name in ("Feeds", "Weather", "Archive", "QuickNotes", "PlayQueue")
}

# The translated missing-tool message each service must emit on exit 127.
NOT_INSTALLED = {
    "Feeds": 'Tr.t("The feed reader is not installed")',
    "Weather": 'Tr.t("The weather service is not installed")',
    "Archive": 'Tr.t("The archive tool is not installed")',
    "QuickNotes": 'Tr.t("The notes service is not installed")',
    "PlayQueue": 'Tr.t("The media service is not installed")',
}

# Signatures and strings other QML/tests rely on; must survive the additions.
PRESERVE = {
    "Feeds": [
        "function start(",
        "function open(",
        "function markRead(",
        "function search(",
        "function setTags(",
        "property var feeds:",
        "function discover(",
    ],
    "Weather": [
        "function fetch(",
        "function lookUp(",
        "function searchCity(",
        "property real temp:",
        "property var forecast:",
        "root.dayparts",
    ],
    "Archive": [
        "function extract(",
        "function create(",
        "function testArchive(",
        "function extractSelected(",
        "property bool needsPassword:",
    ],
    "QuickNotes": [
        "function open(",
        "function set(",
        "function valid(",
        "function jumpTo(",
        "function searchBodies(",
        "property var notes:",
    ],
    "PlayQueue": [
        "function playList(",
        "function open(",
        "function validStreamUrl(",
        "function next(",
        "property var queue:",
        "property string playlistNote:",
    ],
}


# ---- 1. uniform status vocabulary ------------------------------------------


@pytest.mark.parametrize("name", sorted(SERVICES))
def test_service_has_busy_note_error_and_missing_tool_text(name):
    text = SERVICES[name]
    for prop in (
        "property bool busy:",
        "property string note:",
        "property string error:",
    ):
        assert re.search(prop, text), "%s: missing %s" % (name, prop)
    assert "not installed" in text, "%s: no graceful missing-tool answer" % name


@pytest.mark.parametrize("name", sorted(SERVICES))
def test_service_has_exactly_one_run_and_one_finished(name):
    text = SERVICES[name]
    assert len(re.findall(r"function run\(", text)) == 1, name
    assert len(re.findall(r"function finished\(", text)) == 1, name


@pytest.mark.parametrize("name", sorted(SERVICES))
def test_finished_resets_busy_and_handles_exit_127(name):
    text = SERVICES[name]
    assert "code === 127" in text, "%s: no exit-127 path" % name
    assert NOT_INSTALLED[name] in text, "%s: no translated missing-tool string" % name
    done = block(text, "function finished(")
    assert re.search(r"busy = false;", done), "%s: finished does not clear busy" % name


@pytest.mark.parametrize("name", sorted(SERVICES))
def test_completion_handler_delegates_to_finished(name):
    text = SERVICES[name]
    assert "root.finished(" in text, "%s: no call to finished()" % name
    assert "onExited" in text or "onStreamFinished" in text, name


# ---- 2. additive: nothing the other QML/tests read may disappear -----------


@pytest.mark.parametrize("name", sorted(SERVICES))
def test_existing_api_is_preserved(name):
    text = SERVICES[name]
    for token in PRESERVE[name]:
        assert token in text, "%s: dropped %s" % (name, token)


# ---- 3. per-service wiring --------------------------------------------------


def test_feeds_finished_reports_failure_as_error():
    done = block(SERVICES["Feeds"], "function finished(")
    assert 'Tr.t("The feed reader could not answer")' in done
    assert "root.error = " in done


def test_weather_fetch_and_lookup_open_the_guard():
    text = SERVICES["Weather"]
    assert "root.run(" in block(text, "function fetch()")
    assert "root.run(" in block(text, "function lookUp()")


def test_archive_probes_for_bsdtar():
    text = SERVICES["Archive"]
    assert "command -v bsdtar" in text
    assert "root.finished(" in text


def test_quicknotes_and_playqueue_route_a_real_command_through_finished():
    notes = SERVICES["QuickNotes"]
    assert "root.run(" in block(notes, "function syncNotes()")
    assert "root.finished(" in notes
    queue = SERVICES["PlayQueue"]
    assert "root.run(" in block(queue, "function saveQueueM3u(")
    assert "root.finished(" in queue
