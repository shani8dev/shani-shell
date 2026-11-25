"""Media Player larger upgrades: M3U radio + Live TV + music library.

Static checks against the three view files (same style as
test_mediaplayer_views_fixes.py): QML is compiled by the render harness, so
these read the views as text — no QML runtime needed.

Covers: radio station history, live-TV sort options + refresh + view-owned
filter/search, music library shuffle + batch play/enqueue + search operators.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TV = ROOT / "shani/Modules/MediaPlayer/LiveTvView.qml"
RADIO = ROOT / "shani/Modules/MediaPlayer/RadioView.qml"
LIB = ROOT / "shani/Modules/MediaPlayer/MusicLibraryView.qml"


def _between(path: Path, start: str, end: str) -> str:
    text = path.read_text()
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


# ---- Radio: history of stations played (Shortwave parity) ----


def test_radio_recent_stations_history():
    text = RADIO.read_text()
    assert "property var recent: []" in text
    assert "function notePlayed(s)" in text
    # plays record themselves in the history (row click and keyboard)
    assert (
        "onClicked: { Radio.play(row.modelData); notePlayed(row.modelData); }" in text
    )
    assert (
        "KeyFocus { onActivated: { Radio.play(row.modelData); notePlayed(row.modelData); } }"
        in text
    )
    # the history is a row of taps back, newest first
    assert "visible: recent.length > 0" in text
    assert "Repeater {\n            model: recent" in text


def test_radio_playing_state_from_the_queue():
    text = RADIO.read_text()
    assert "function played(s)" in text
    assert "PlayQueue.current === s.url" in text
    assert "readonly property bool playing: played(row.modelData)" in text


# ---- Live TV: sort options + refresh ----


def test_live_tv_sort_options():
    text = TV.read_text()
    assert (
        'Tr.t("Playlist order")' in text
        and 'Tr.t("By name")' in text
        and 'Tr.t("By group")' in text
    )
    assert 'selected: sort === "name"; onClicked: sort = "name"' in text
    assert 'selected: sort === "group"; onClicked: sort = "group"' in text
    assert 'selected: sort === ""; onClicked: sort = ""' in text


def test_live_tv_refresh_button():
    text = TV.read_text()
    assert 'icon: "view-refresh"' in text
    assert 'tip: Tr.t("Refresh")' in text
    assert "LiveTv.source ? LiveTv.load(LiveTv.source) : LiveTv.loadDefaults()" in text


def test_live_tv_view_owns_search_and_filter():
    # search operators (a term matches name, group or url) and sorting are
    # view-level; the ListView and counts read the view's `shown`
    text = TV.read_text()
    assert "readonly property var shown: LiveTv.channels.filter(matches)" in text
    assert "function matches(c)" in text
    assert (
        '(c.name + " " + (c.group || "") + " " + (c.url || "")).toLowerCase()' in text
    )
    assert (
        "return text.split(/\\s+/).filter(t => t).every(t => hay.indexOf(t) >= 0);"
        in text
    )
    assert "model: shown" in text
    assert 'text: Tr.t("%1 channels", shown.length)' in text
    assert (
        'visible: LiveTv.loading || LiveTv.error !== "" || shown.length === 0' in text
    )


def test_live_tv_sort_orders_names_and_groups():
    text = TV.read_text()
    assert (
        'sort === "name" ? (a.name + " " + a.group).localeCompare(b.name + " " + b.group)'
        in text
    )
    assert (
        'sort === "group" ? (a.group + " " + a.name).localeCompare(b.group + " " + b.name)'
        in text
    )


# ---- Music Library: search operators, shuffle, batch play ----


def test_music_library_search_operators():
    # terms match title/artist/album; a leading - drops a match
    text = LIB.read_text()
    assert "for (const t of text.split(/\\s+/))" in text
    assert 't.startsWith("-")' in text
    assert "minus.push(t.slice(1).toLowerCase())" in text
    assert "want.push(t.toLowerCase())" in text
    assert (
        "return want.every(t => hay.indexOf(t) >= 0) && minus.every(t => hay.indexOf(t) < 0);"
        in text
    )


def test_music_library_shuffle_on_the_songs_tab():
    text = LIB.read_text()
    assert 'text: Tr.t("Shuffle")' in text
    assert (
        'visible: lib.album === null && lib.tab === "songs" && lib.artist === ""'
        in text
    )
    assert "PlayQueue.shuffle = true" in text
    assert "MusicLibrary.play(lib.songsShown," in text


def test_music_library_batch_select_and_play_selected():
    text = LIB.read_text()
    assert "property var selected: []" in text
    assert "property bool selectMode: false" in text
    assert "function toggleSelected(p)" in text
    assert "lib.selected.indexOf(p)" in text
    assert "function playSelected()" in text
    assert "PlayQueue.playList(lib.selected, 0)" in text
    # the rows carry a checkbox, and the header a pick toggle + Play selected
    assert 'text: songRow.isSelected ? "✓" : ""' in text
    assert "readonly property bool isSelected" in text
    assert 'icon: "edit-select-all"' in text
    assert 'text: Tr.t("Play selected")' in text
    assert "lib.selected.length > 0" in text
