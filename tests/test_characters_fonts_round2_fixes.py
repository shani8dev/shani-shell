"""Static assertions for Characters/Fonts round-2 UX fixes.

CharactersPanel.qml and FontsPanel.qml are render-harness QML, so tests assert
source wiring rather than driving a running shell.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHARS = ROOT / "shani/Modules/Characters/CharactersPanel.qml"
FONTS = ROOT / "shani/Modules/Fonts/FontsPanel.qml"


def chars():
    return CHARS.read_text(encoding="utf-8")


def fonts():
    return FONTS.read_text(encoding="utf-8")


def test_characters_copy_feedback_and_enter_copies_first_result():
    t = chars()
    # inline copy feedback for mouse, keyboard and AT activation
    assert 'property string copiedLabel: ""' in t
    assert "function copyChar(entry)" in t
    assert "Characters.copy(entry)" in t
    assert "win.copiedLabel = entry.ch" in t
    assert "copiedTimer.restart()" in t
    assert (
        'Timer { id: copiedTimer; interval: 1800; onTriggered: win.copiedLabel = "" }'
        in t
    )
    # every copy path goes through the feedback wrapper
    assert "onClicked: win.copyChar(cell.modelData)" in t
    assert "onActivated: win.copyChar(cell.modelData)" in t
    assert "Accessible.onPressAction: win.copyChar(cell.modelData)" in t
    # search keyboard flow: Enter in the search field copies the first result
    assert (
        "onAccepted: if (Characters.results.length > 0) win.copyChar(Characters.results[0])"
        in t
    )
    # footer surfaces the copy confirmation
    assert 'Tr.t("Copied %1 · Esc closes", win.copiedLabel)' in t


def test_characters_scroll_to_top_on_results_change():
    t = chars()
    assert "Connections {" in t
    assert "target: Characters" in t
    assert "function onResultsChanged() { grid.contentY = 0 }" in t


def test_characters_grid_has_accessible_name():
    t = chars()
    assert "Accessible.role: Accessible.List" in t
    assert 'Accessible.name: Tr.t("Character results")' in t


def test_fonts_copy_feedback_and_refresh_clears_stale_install_note():
    t = fonts()
    assert 'property string copiedFamily: ""' in t
    assert (
        'Timer { id: copiedTimer; interval: 1800; onTriggered: win.copiedFamily = "" }'
        in t
    )
    assert "copiedFamily = family;" in t
    assert "copiedTimer.restart()" in t
    assert 'Tr.t("Copied %1 · Esc closes", win.copiedFamily)' in t
    # refresh clears stale install/copy state before re-listing
    refresh = t.split("function refresh() {", 1)[1].split("\n    }", 1)[0]
    for line in ('installNote = "";', 'copiedFamily = "";', "copiedTimer.stop();"):
        assert line in refresh, f"{line} missing from refresh()"


def test_fonts_file_preview_samples_scale_with_font_scale():
    t = fonts()
    assert (
        "font.family: fileFont.name; font.pixelSize: Theme.px(16) * Theme.fontScale"
        in t
    )
    assert (
        "font.family: fileFont.name; font.pixelSize: Theme.px(modelData) * Theme.fontScale"
        in t
    )
