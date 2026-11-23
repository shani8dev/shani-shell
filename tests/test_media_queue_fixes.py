"""Three static checks for the pass-20 media-queue fixes.

QML here is compiled by the render harness, so these read the sources as text:
remove/clear, a three-state repeat, and a Back history that retraces shuffle.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / "shani/Services/PlayQueue.qml").read_text()
WINDOW = (ROOT / "shani/Modules/MediaPlayer/MediaPlayerWindow.qml").read_text()


def test_remove_one_and_clear_queue():
    # the service owns the array: removing a row shifts `current`, clearing empties it
    assert "function remove(i)" in QUEUE and "q.splice(i, 1)" in QUEUE
    assert "function clear()" in QUEUE and "index = -1" in QUEUE
    # both are wired into the queue panel: a × per row and a header button
    assert '"list-remove"' in WINDOW and "PlayQueue.remove(row.index)" in WINDOW
    assert 'Tr.t("Clear")' in WINDOW and "PlayQueue.clear()" in WINDOW


def test_repeat_is_three_state_with_mpris_playlist():
    assert 'property string repeat: "off"' in QUEUE
    assert 'readonly property bool repeatOne: repeat === "one"' in QUEUE
    # ended() loops in "all", replays in "one", and MPRIS Playlist maps to all
    assert 'repeat === "all"' in QUEUE and '"Playlist"' in QUEUE
    assert 'c.value === "Playlist" ? "all"' in QUEUE
    assert "onRepeatChanged: tellMpris()" in QUEUE
    # the toolbar button cycles off -> all -> one; nothing writes the old flag
    assert 'PlayQueue.repeat === "off" ? "all"' in WINDOW
    assert '"media-playlist-repeat-song"' in WINDOW
    assert "PlayQueue.repeatOne =" not in WINDOW


def test_previous_retraces_shuffle_history():
    assert "property var history: []" in QUEUE
    # forward navigation records where it came from; Back pops instead of index-1
    assert "h.push(index)" in QUEUE and "h.pop()" in QUEUE
    # a fresh queue starts with no history to pop
    assert QUEUE.count("root.history = []") >= 3
    assert "PlayQueue.previous()" in WINDOW
