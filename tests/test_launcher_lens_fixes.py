"""Static regressions for launcher/lens gaps not listed in docs/GAPS*.md.

Both surfaces are QML singletons/panels that need a running shell, so each test
asserts the exact source wiring rather than driving a QML runtime.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER = (ROOT / "shani/Modules/Launcher/Launcher.qml").read_text(encoding="utf-8")
LENS = (ROOT / "shani/Modules/Lens/LensPanel.qml").read_text(encoding="utf-8")


def block(src, start, end):
    return src.split(start, 1)[1].split(end, 1)[0]


def test_launcher_ignores_stale_search_answers():
    # Three async searches finish out of order while the person keeps typing;
    # only an answer that still belongs to the current query may be stored.
    providers = block(LAUNCHER, "id: providerSearch", "\n    }")
    assert (
        'providerSearch.terms.join(" ") !== win.q.trim().split(/\\s+/).join(" ")'
        in providers
    )
    assert "win.provided = JSON.parse(text)" in providers

    names = block(LAUNCHER, "id: fileSearch", "\n    }")
    assert "fileSearch.query === win.q.trim()" in names
    assert "win.found = text.trim()" in names

    inside = block(LAUNCHER, "id: contentSearch", "\n    }")
    assert "contentSearch.query === win.q.trim()" in inside
    assert "win.inside = text.trim()" in inside


def test_launcher_disarms_hover_when_reopened():
    # hoverArmed is sticky; without this a pointer resting where a row used to
    # be steals the selection from the top result on the next open.
    visible = block(LAUNCHER, "onVisibleChanged: {", "\n    // ---- drawing")
    assert "hoverArmed = false;" in visible
    assert visible.index("hoverArmed = false;") < visible.index(
        "search.forceActiveFocus()"
    )


def test_launcher_contact_copy_action_is_reachable():
    # contact results define copy: () => ... but nothing called it. Ctrl+C must
    # not swallow a copy of text selected in the search field itself.
    pressed = block(
        LAUNCHER,
        "Keys.onPressed: e => {",
        "\n                     Keys.onReturnPressed",
    )
    assert "Qt.Key_C && (e.modifiers & Qt.ControlModifier)" in pressed
    assert 'search.selectedText === ""' in pressed
    assert "win.flat[win.sel].copy();" in pressed


def test_launcher_file_urls_use_the_shared_encoder():
    # A path with #, ? or % broke both opening and previewing a result; Files
    # already ships uriOf(), so no second encoder is needed. Opening a hit goes
    # through Files' own dispatcher, the same route a double click takes.
    assert "run: () => Files.openEntry(p)" in LAUNCHER
    assert "Qt.openUrlExternally(Files.uriOf(p))" not in LAUNCHER
    assert 'Files.uriOf(row.modelData.thumb || "")' in LAUNCHER
    assert "Files.uriOf(win.lookPdfImage)" in LAUNCHER
    assert "Files.uriOf(win.current.path)" in LAUNCHER
    assert '"file://" + p' not in LAUNCHER


def test_lens_actions_are_guarded_and_escape_closes_from_anywhere():
    # Save/Open acted on an empty image; Enter asked before a result existed;
    # Escape only worked while the question field had focus.
    assert 'enabled: Lens.image !== ""; onClicked: { Lens.save()' in LENS
    assert 'enabled: Lens.image !== ""; onClicked: { Lens.openImage()' in LENS
    assert 'onAccepted: if (Lens.phase === "ready") Lens.ask(text)' in LENS
    focus_item = block(LENS, "Item { anchors.fill: parent; focus: win.visible", "\n")
    assert "Keys.onEscapePressed: Lens.close()" in focus_item
    assert 'Accessible.name: Tr.t("Ask Chronoa about this…")' in LENS
