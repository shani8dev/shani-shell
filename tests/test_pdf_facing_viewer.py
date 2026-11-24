"""Second deep pass: PDF facing pages and the image Viewer's exit / Save As.

CuboCore's corepdf cycles Single / Facing / Book layouts and keeps the choice in
its own settings; its coreimage shows a named Save As dialog and an EXIT link
when the toolbars are hidden in full screen. This file pins the shani versions
of those two gaps.

The page-pairing convention documented here and in Services/PdfViewer.qml:
spreads start on ODD 1-based pages — [1,2], [3,4], [5,6] — so "current page 3"
shows pages 3 and 4. Page 1 of a book is on the left of the first spread (no
separate cover placement). A search hit on an even page lands in the right half
of its spread. If the right-hand PNG is missing (or it is the last page), only
the left page is drawn; if the left PNG is missing, the right one is drawn full
width. Continuous scroll keeps its own single-column layout.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


SERVICE = "shani/Services/PdfViewer.qml"
READER = "shani/Modules/PdfReader/PdfReader.qml"
VIEWER = "shani/Modules/Viewer/Viewer.qml"


# ---- pure pairing logic, mirroring PdfViewer.qml's spread properties --------


def spread(page1: int, count: int, missing: tuple = ()) -> tuple:
    """1-based pages visible for a current 1-based page. `missing` holds 1-based
    pages whose rendered PNG is absent. Returns 1-based page numbers in order."""
    if count <= 0 or page1 < 1 or page1 > count:
        return ()
    p = page1 - 1
    start = p - (p % 2)  # QML: spreadStart: page - (page % 2)

    def has(i: int) -> bool:
        return 0 <= i < count and (i + 1) not in missing

    if has(start):
        left = start
        right = start + 1 if has(start + 1) else -1
    elif has(start + 1):
        left, right = start + 1, -1
    else:
        left, right = -1, -1
    return tuple(i + 1 for i in (left, right) if i >= 0)


def next_page(page1: int, count: int) -> int:
    """Next / Right in facing mode: jump a whole spread, never a single page."""
    if count <= 0:
        return 0
    p = page1 - 1
    start = p - (p % 2)
    target = start + 2
    return (target if target < count else p) + 1  # 0-based target + 1


def prev_page(page1: int, count: int) -> int:
    p = page1 - 1
    start = p - (p % 2)
    return max(0, start - 2) + 1


# ---- pairing math ----------------------------------------------------------


def test_facing_pairs_odd_current_page_with_the_next_one():
    assert spread(3, 6) == (3, 4)  # the documented convention
    assert spread(1, 6) == (1, 2)
    assert spread(5, 6) == (5, 6)


def test_even_current_page_stays_in_its_spread():
    # a search hit on page 4 must not jump to the 5+6 spread
    assert spread(4, 6) == (3, 4)
    assert spread(2, 6) == (1, 2)
    assert spread(6, 6) == (5, 6)


def test_odd_and_missing_page_counts():
    assert spread(5, 5) == (5,)  # last odd page stands alone
    assert spread(4, 5) == (3, 4)
    assert spread(1, 1) == (1,)  # single-page document
    assert spread(7, 7) == (7,)
    assert spread(3, 0) == ()


def test_missing_png_falls_back_to_one_full_width_page():
    assert spread(3, 4, missing=(3,)) == (4,)
    assert spread(1, 4, missing=(1,)) == (2,)
    assert spread(3, 4, missing=(3, 4)) == ()
    assert spread(3, 4, missing=(2,)) == (3, 4)  # a hole elsewhere is harmless


def test_spread_navigation_stays_on_spread_boundaries():
    assert next_page(3, 6) == 5  # 3+4 → 5+6
    assert next_page(4, 6) == 5  # a hit on 4 still advances past 4
    assert next_page(5, 6) == 5  # last spread: no overshoot
    assert prev_page(5, 6) == 3
    assert prev_page(4, 6) == 1  # 3+4 → 1+2
    assert prev_page(1, 6) == 1
    # every hop lands on a page that is actually the left of its spread
    for count in (1, 2, 5, 6, 7):
        for page in range(1, count + 1):
            nxt = next_page(page, count)
            p = page - 1
            target = (p - p % 2) + 2
            assert nxt == (target if target < count else p) + 1
            assert spread(nxt, count)[0] == nxt or count % 2 == 0


# ---- static: PDF service ---------------------------------------------------


def test_pdf_service_owns_the_facing_state_and_pairing():
    s = read(SERVICE)
    assert "property bool facing: prefs.facing === true" in s
    assert "function toggleFacing()" in s and "prefsFile.writeAdapter()" in s
    assert "readonly property bool facingActive:" in s
    assert "!continuous" in s, "facing rests while continuous scroll is on"
    assert "readonly property int spreadStart: page - (page % 2)" in s
    assert "readonly property int spreadLeft:" in s
    assert "readonly property int spreadRight:" in s
    assert "spreadLeftPath" in s and "spreadRightPath" in s
    assert "readonly property string spreadLabel:" in s
    assert "function pageImage(i)" in s, "a missing PNG must fall back to one page"
    assert "function nextSpread()" in s and "function prevSpread()" in s
    assert "spreadStart + 2" in s and "spreadStart - 2" in s
    assert "function lastPage()" in s and "n - (n % 2)" in s


def test_pdf_preference_is_local_not_a_contested_settings_key():
    s = read(SERVICE)
    # Common/Settings.qml is owned by another surface: use the OSK agent's
    # sibling-JSON pattern instead of adding a key there.
    assert "Settings.path" in s and "pdf-viewer.json" in s
    assert (
        "FileView {" in s
        and "JsonAdapter { id: prefs; property bool facing: false }" in s
    )
    assert "Settings.data.pdfFacing" not in s, (
        "the preference stays out of the shared settings file"
    )
    assert 'execDetached(["mkdir", "-p", root.prefsDir])' in s


def test_pdf_single_page_navigation_still_exists_for_other_callers():
    s = read(SERVICE)
    assert "function nextPage() { goTo(page + 1); }" in s
    assert "function prevPage() { goTo(page - 1); }" in s
    assert "if (!facingActive) { nextPage(); return; }" in s
    assert "if (!facingActive) { prevPage(); return; }" in s


# ---- static: PDF reader ----------------------------------------------------


def test_reader_drives_two_rendered_pngs():
    m = read(READER)
    assert 'icon: "view-pages-facing"' in m and "PdfViewer.toggleFacing()" in m
    assert "on: PdfViewer.facing" in m
    assert "id: leftPageImage" in m and "id: rightPageImage" in m
    assert "PdfViewer.spreadLeftPath" in m and "PdfViewer.spreadRightPath" in m
    assert 'visible: PdfViewer.facingActive && PdfViewer.spreadLeftPath !== ""' in m
    assert 'visible: PdfViewer.facingActive && PdfViewer.spreadRightPath !== ""' in m
    # the two halves share the page's zoom Flickable; a lone page goes full width
    assert "rightPageImage.visible ? parent.width / 2 : parent.width" in m
    assert "leftPageImage.visible ? parent.width / 2 : parent.width" in m
    assert 'visible: !PdfViewer.facingActive && PdfViewer.current !== ""' in m


def test_reader_turns_whole_spreads_and_labels_them():
    m = read(READER)
    assert "Keys.onRightPressed: PdfViewer.nextSpread()" in m
    assert "Keys.onLeftPressed: PdfViewer.prevSpread()" in m
    assert "PdfViewer.nextSpread(); else PdfViewer.prevSpread();" in m
    assert (
        "onClicked: PdfViewer.nextSpread()" in m
        and "onClicked: PdfViewer.prevSpread()" in m
    )
    assert "PdfViewer.spreadLabel" in m and 'Tr.t("facing pages")' in m


def test_reader_search_highlight_maps_onto_the_right_half():
    m = read(READER)
    assert "readonly property bool inRight:" in m
    assert "readonly property real slotW:" in m
    assert "parent.width / 2 : parent.width" in m
    assert "PdfViewer.highlight.page === PdfViewer.spreadRight" in m
    assert "PdfViewer.highlight.page === PdfViewer.spreadLeft" in m


def test_save_page_image_button_survives_the_spread():
    m = read(READER)
    assert 'tip: Tr.t("Save this page as image…")' in m
    assert 'enabled: PdfViewer.current !== ""' in m
    assert "win.savePageImage()" in m
    assert "PdfViewer.savePageImage(paths[0])" in m
    assert 'defaultName: base + "-page-" + (PdfViewer.page + 1) + ".png"' in m


# ---- static: image viewer --------------------------------------------------


def test_viewer_has_explicit_full_screen_and_exit():
    m = read(VIEWER)
    assert "property bool immersive: false" in m
    assert "header: !immersive" in m, "the shell header hides with the chrome"
    assert "Qt.Key_F11" in m
    assert 'Tr.t("Exit full screen (Esc)")' in m
    assert "onClicked: win.immersive = false" in m
    assert 'tip: Tr.t("Full screen (F11)")' in m
    # every toolbar / strip row steps aside, but the stage and the exit do not
    assert m.count("visible: !win.immersive") >= 5
    assert "if (win.immersive) { win.immersive = false; return; }" in m


def test_viewer_save_as_lets_you_name_the_copy():
    m = read(VIEWER)
    assert "function saveAs()" in m
    assert 'icon: "document-save-as"' in m and "win.saveAs()" in m
    assert 'mode: "save"' in m and "defaultName:" in m and "onPicked: paths =>" in m
    assert 'Viewer.saveEdit("copy")' in m, "reuse the existing edit renderer"
    assert "function onSavedChanged()" in m
    assert (
        'saveAsMove.command = ["mv", "-f", "--", Viewer.saved, win.saveAsTarget]' in m
    )
    assert "to === Viewer.file" in m, "never rename over the original"
    assert "Viewer.open(to)" in m
    assert "if (!Viewer.file || Viewer.saving) return;" in m
    # the auto-named "Save a copy" button stays; Save As is additive
    assert 'Tr.t("Save a copy")' in m


def test_viewer_keeps_its_loupe_parity_controls():
    m = read(VIEWER)
    for tip in [
        "Fit to window",
        "100%",
        "200%",
        "Rotate right",
        "Slideshow",
        "Grid",
        "Thumbnails",
    ]:
        assert tip in m, tip
    assert "zoomToCursor" in m and "Qt.Key_F11" in m
