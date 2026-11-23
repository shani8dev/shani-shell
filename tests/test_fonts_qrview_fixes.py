"""Static assertions for the font-browser craft fixes (pass-22 utility apps).

FontsPanel.qml is compiled by the render harness, so these check the source
wiring rather than running QML: the search filters every font before the
400-item cap, and a row click queries that one font and marks user installs.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "shani/Modules/Fonts/FontsPanel.qml"


def fonts_source():
    return FONTS.read_text(encoding="utf-8")


def test_font_search_filters_all_fonts_before_the_400_cap_and_shows_total():
    t = fonts_source()
    # a search field drives win.searchText
    assert "id: searchField" in t
    assert 'objectName: "font-search"' in t
    assert 'Tr.t("Search fonts by family or style")' in t
    assert "onTextChanged: win.searchText = text" in t
    # the full fc-list result is kept separately, so search covers all N fonts
    assert "property var allFonts: []" in t
    assert "win.allFonts = out" in t
    assert 'command: ["fc-list", ":", "family", "style", "file"]' in t
    # one function filters by family/style on the whole set, THEN caps at 400
    assert "function applyFilter()" in t
    assert '(f.family || "").toLowerCase().indexOf(q) >= 0' in t
    assert '(f.style || "").toLowerCase().indexOf(q) >= 0' in t
    assert "filteredCount = matched.length" in t
    assert "fonts = matched.slice(0, 400)" in t
    assert "truncated = matched.length > 400" in t
    assert "win.applyFilter()" in t
    # the count shows the total (and the match count while searching)
    assert "property int filteredCount: 0" in t
    assert 'Tr.t("%1 of %2 styles", win.filteredCount, win.totalFonts)' in t
    assert 'Tr.t("%1 styles", win.totalFonts)' in t
    # a no-match search gets its own empty state, not "fc-list found nothing"
    assert 'Tr.t("No matching fonts")' in t


def test_font_details_and_user_badge_are_lazy_on_selection():
    t = fonts_source()
    # fc-list carries the file path, and each entry knows if it is user-installed
    assert "const file = line.slice(0, ci).trim();" in t
    assert "file: file" in t
    assert "user: file.indexOf(" in t
    assert "/.local/share/fonts/" in t
    # one fc-query, only for the selected row: family/style/full name/version
    assert "function selectFont(f)" in t
    assert 'fontDetails.command = ["fc-query"' in t
    assert "%{fullname[0]}" in t
    assert "%{fontversion}" in t
    assert "fontDetails.running = true" in t
    assert "copyFamily(f.family)" in t  # the original click-to-copy is kept
    assert "win.selectedDetails = [" in t
    # the details card and the list badge render that metadata
    assert 'objectName: "font-details"' in t
    assert "visible: win.selectedFont !== null" in t
    assert 'f.user ? "  [" + Tr.t("User-installed") + "]" : ""' in t
    assert "visible: row.modelData.user === true" in t
    assert 'text: Tr.t("User")' in t
