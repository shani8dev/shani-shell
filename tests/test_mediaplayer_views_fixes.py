"""Media Player views: search/empty states, clear affordances, keyboard access.

Static checks against the three view files we own; no QML runtime needed.
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


def test_live_tv_empty_action_label_matches_its_action():
    # The action loads the free starter channels; the old "Browse…" label
    # promised a file picker and opened nothing of the kind.
    empty = _between(TV, "    EmptyState {", "    ListView {")
    assert 'Tr.t("Free picks")' in empty
    assert "LiveTv.loadDefaults()" in empty
    assert 'Tr.t("Browse…")' not in empty


def test_live_tv_filtered_empty_state_clears_filters():
    empty = _between(TV, "    EmptyState {", "    ListView {")
    assert "readonly property bool filteredEmpty" in empty
    assert "LiveTv.channels.length > 0 && LiveTv.shown.length === 0" in empty
    assert 'LiveTv.error !== "" || LiveTv.shown.length === 0' in empty
    assert 'Tr.t("No matches")' in empty and 'Tr.t("Try a different search")' in empty
    assert 'find.text = ""; LiveTv.search = ""; LiveTv.group = ""' in empty


def test_radio_rows_are_keyboard_activatable():
    # Live TV and Library rows have KeyFocus; Radio rows were mouse-only.
    assert "KeyFocus { onActivated: Radio.play(row.modelData) }" in RADIO.read_text()


def test_radio_search_has_a_visible_clear_affordance():
    text = RADIO.read_text()
    assert 'visible: Radio.showing.startsWith("search:")' in text
    assert 'icon: "edit-clear"' in text
    assert 'onClicked: { find.text = ""; Radio.show("featured"); }' in text
    assert 'Radio.showing.startsWith("search:") ? Tr.t("No matches")' in text


def test_library_search_empty_state_clears_the_query():
    text = LIB.read_text()
    assert "readonly property bool nothingFound" in text
    assert "lib.albumsShown.length === 0" in text
    assert "lib.songsShown.length === 0" in text
    assert "videoList.model.length === 0" in text
    assert 'title: Tr.t("No matches")' in text
    assert 'onAction: { find.text = ""; lib.query = ""; }' in text
    assert "id: find" in text
    # "No music yet" must not double up with "No matches" while searching
    assert 'visible: lib.q === "" && lib.tab !== "videos"' in text
