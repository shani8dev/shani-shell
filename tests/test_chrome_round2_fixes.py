"""Round two of uniform window chrome: the original app windows.

Static guards only (no QML is instantiated): the first pass covered the newer
surfaces, this pins the same close path, header and Ctrl keys for the apps that
came before it.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

APPWINDOW = ROOT / "shani/Common/AppWindow.qml"
WINDOWS = {
    "Files": ROOT / "shani/Modules/Files/FilesPanel.qml",
    "TextEditor": ROOT / "shani/Modules/TextEditor/TextEditorPanel.qml",
    "Mail": ROOT / "shani/Modules/Mail/MailWindow.qml",
    "Notes": ROOT / "shani/Modules/Notes/NotesPanel.qml",
    "Calendar": ROOT / "shani/Modules/Calendar/CalendarPanel.qml",
}
UPDATES = ROOT / "shani/Modules/Settings/SettingsUpdates.qml"


def src(path):
    return path.read_text(encoding="utf-8")


def flag_of(text):
    m = re.search(r"^    visible: Ui\.(\w+)$", text, re.M)
    assert m, "window has no root-level Ui visibility flag"
    return m.group(1)


def test_01_appwindow_owns_escape_ctrl_w_ctrl_f_and_ctrl_r():
    s = src(APPWINDOW)
    keys = s[s.index("Keys.onPressed: e => {") : s.index("// the Menu key")]
    assert "win.shortcutSearch.forceActiveFocus()" in keys
    assert "win.shortcutRefresh()" in keys
    assert keys.count("win.requestClose()") == 2  # Escape and Ctrl+W
    assert "property var shortcutSearch: null" in s
    assert "property var shortcutRefresh: null" in s


def test_02_every_original_window_has_a_stable_name_and_a_gone_flag_reset():
    for name, path in WINDOWS.items():
        s = src(path)
        assert "AppWindow {" in s, name
        assert re.search(r'^    appName: "[^"]+"', s, re.M), name
        flag = flag_of(s)
        # Files resets its flag through the service's hide(), the others directly
        assert re.search(
            rf"^    onGone: (Ui\.{flag} = false|Files\.hide\(\))$", s, re.M
        ), name


def test_03_text_editor_moves_app_keys_off_the_central_shortcuts():
    s = src(WINDOWS["TextEditor"])
    assert "e.key === Qt.Key_R && shift) recentDialog.open()" in s
    assert "e.key === Qt.Key_W && shift) win.closeTab(TextDocs.active)" in s
    assert "e.key === Qt.Key_R) recentDialog.open()" not in s
    assert "e.key === Qt.Key_W) win.closeTab(" not in s
    assert 'tip: "Open recent (Ctrl+Shift+R)"' in s
    assert "Ctrl+R refreshes: both belong to AppWindow" in s
    # the find bar is local: Ctrl+F opens it rather than focusing a hidden field
    assert "win.finding = true; win.replacing = false; findField.text" in s


def test_04_files_moves_close_tab_to_ctrl_shift_w_and_frees_ctrl_f():
    s = src(WINDOWS["Files"])
    assert (
        "control && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_W"
        " && Files.tabs.length > 1) { Files.closeTab();" in s
    )
    assert not re.search(r"if \(control && event\.key === Qt\.Key_W", s)
    # plain Ctrl+F is central; Ctrl+Shift+F keeps its own filter popover
    assert "shortcutSearch: searchBox" in s
    assert (
        "event.key === Qt.Key_F) {\n                searchBox.forceActiveFocus()"
        not in s
    )
    assert "event.key === Qt.Key_F) {\n                win.toggleFilters()" in s


def test_05_central_refresh_hooks_resolve_to_real_actions():
    expected = {
        "Files": ("function refresh() { dir.reload(); }", "win.refresh()"),
        "Mail": ("function refresh() { Mail.refresh(); }", "win.refresh()"),
        "Calendar": ("function refresh() { Agenda.refresh(); }", "win.refresh()"),
    }
    for name, (fn, call) in expected.items():
        s = src(WINDOWS[name])
        assert re.search(rf"^    shortcutRefresh: win\.refresh", s, re.M), name
        assert fn in s, name
        assert call in s, name
    # no local Ctrl+R Shortcut remains in the calendar: AppWindow owns the key
    assert 'sequence: "Ctrl+R"' not in src(WINDOWS["Calendar"])


def test_06_search_hooks_point_at_a_focusable_field_or_document_the_skip():
    assert re.search(
        r"^    shortcutSearch: searchField\.input", src(WINDOWS["Mail"]), re.M
    )
    assert re.search(
        r"^    shortcutSearch: searchField\.input", src(WINDOWS["Calendar"]), re.M
    )
    assert re.search(r"^    shortcutSearch: filterField", src(WINDOWS["Notes"]), re.M)
    notes = src(WINDOWS["Notes"])
    assert "Ctrl+R is AppWindow's; notes autosave" in notes


def test_07_header_actions_live_in_one_tools_row_with_their_names_kept():
    for name, path in WINDOWS.items():
        s = src(path)
        assert s.count("\n    tools: [") == 1, name
        assert not re.search(r"^    id: bar\b", s, re.M), name  # no bespoke header
        assert "startSystemMove" not in s, name
    files = src(WINDOWS["Files"])
    assert 'tip: Tr.t("Refresh (F5)"); onClicked: win.refresh()' in files
    mail = src(WINDOWS["Mail"])
    assert 'tip: Tr.t("Refresh"); size: Theme.px(26); on: Mail.busy' in mail
    # the moved button is gone from the folders pane; the hints still say Refresh
    assert mail.count('icon: "view-refresh"') == 1
    assert 'icon: "insert-image-symbolic"' in src(WINDOWS["Notes"])


def test_08_every_close_path_goes_through_request_close():
    for name, path in WINDOWS.items():
        s = src(path)
        assert not re.search(r"Keys\.onEscapePressed:[^\n]*Ui\.\w+ = false", s), name
        assert not re.search(r"onActivated:[^\n]*Ui\.\w+ = false", s), name
    editor = src(WINDOWS["TextEditor"])
    assert "win.requestClose();   // the unsaved-work guard" in editor
    assert "Ui.textEditor = false" not in editor.replace(
        "onGone: Ui.textEditor = false", ""
    )
    files = src(WINDOWS["Files"])
    assert "else\n                win.requestClose();" in files
    calendar = src(WINDOWS["Calendar"])
    assert calendar.count("win.requestClose()") >= 2
    assert "Ui.calendar = false" not in calendar.replace(
        "onGone: Ui.calendar = false", ""
    )
    # Mail's layered Escape stays local; the final fall-through is AppWindow's
    mail = src(WINDOWS["Mail"])
    assert "win.mailKey(e)" in mail and "win.clearFilters()" in mail


def test_09_updates_panel_checks_on_ctrl_r_without_stealing_window_keys():
    s = src(UPDATES)
    assert "Keys.onPressed: event => {" in s
    assert (
        "event.key === Qt.Key_R) {\n            Updates.check(); event.accepted = true;"
        in s
    )
    assert "Ctrl+W (close) belong to the hosting Settings window" in s
    assert "Qt.Key_W" not in s
