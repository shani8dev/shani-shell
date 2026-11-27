"""Static guards for uniform app-window chrome and keyboard shortcuts.

Runtime QML is not instantiated here: these pin the source wiring that gives
every owned window the same header, close path and standard Ctrl keys.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

APPWINDOW = ROOT / "shani/Common/AppWindow.qml"
WINDOWS = {
    "Dictionary": ROOT / "shani/Modules/Dictionary.qml",
    "Teleprompter": ROOT / "shani/Modules/Teleprompter.qml",
    "NetTools": ROOT / "shani/Modules/NetTools.qml",
    "DatabaseBrowser": ROOT / "shani/Modules/DatabaseBrowser.qml",
    "PodcastWindow": ROOT / "shani/Modules/MediaPlayer/PodcastWindow.qml",
}
RESTORE = ROOT / "shani/Modules/Settings/SettingsSystemRestore.qml"


def src(path):
    return path.read_text(encoding="utf-8")


def flag_of(text):
    m = re.search(r"^    visible: Ui\.(\w+)$", text, re.M)
    assert m, "window has no root-level Ui visibility flag"
    return m.group(1)


def test_01_appwindow_exposes_defaulted_shortcut_hooks_and_a_window_name():
    s = src(APPWINDOW)
    # additive: existing apps keep their bindings when both hooks are null
    assert "property var shortcutSearch: null" in s
    assert "property var shortcutRefresh: null" in s
    assert "property alias tools: toolStrip.actions" in s
    assert "Accessible.role: Accessible.Window" in s
    assert "Accessible.name: win.title" in s
    keys = s[s.index("Keys.onPressed: e => {") : s.index("// the Menu key")]
    assert "win.shortcutSearch.forceActiveFocus()" in keys
    assert "win.shortcutRefresh()" in keys
    assert keys.count("win.requestClose()") == 2  # Escape and Ctrl+W


def test_02_every_owned_window_declares_identity_and_sized_in_theme_pixels():
    for name, path in WINDOWS.items():
        s = src(path)
        assert "AppWindow {" in s, name
        assert re.search(r'^    appName: "[^"]+"', s, re.M), name
        assert re.search(r"^    implicitWidth: Theme\.px\(\d+\)", s, re.M), name
        assert re.search(r"^    implicitHeight: Theme\.px\(\d+\)", s, re.M), name


def test_03_every_owned_window_visibility_and_gone_share_one_ui_flag():
    for name, path in WINDOWS.items():
        s = src(path)
        flag = flag_of(s)
        assert re.search(rf"^    onGone: Ui\.{flag} = false$", s, re.M), name
        assert "visible: true" not in s, name


def test_04_escape_and_ctrl_w_close_through_the_guard_only():
    s = src(APPWINDOW)
    keys = s[s.index("Keys.onPressed: e => {") : s.index("// the Menu key")]
    assert "Qt.Key_Escape" in keys and re.search(r"Qt\.Key_W\b", keys)
    for name, path in WINDOWS.items():
        w = src(path)
        assert not re.search(r"Keys\.onEscapePressed:[^\n]*Ui\.", w), name
        assert not re.search(r"Keys\.onEscapePressed:[^\n]*win\.visible = false", w), (
            name
        )
        assert not re.search(r"Keys\.onPressed:[^\n]*Qt\.Key_Escape", w), name
        # no owned window claims Ctrl+W locally; AppWindow owns it
        assert not re.search(r"Qt\.Key_W\b", w), name
        if "Keys.onEscapePressed" in w:  # StartupManager unwinds a confirmation
            assert "win.requestClose()" in w, name


def test_05_ctrl_f_focuses_the_search_field_or_documents_the_skip():
    for name in ("Dictionary", "NetTools", "PodcastWindow"):
        s = src(WINDOWS[name])
        assert re.search(r"^    shortcutSearch: \w[\w.]*", s, re.M), name
    for name in ("Teleprompter", "DatabaseBrowser"):
        s = src(WINDOWS[name])
        assert "Ctrl+F" in s and "N/A" in s, name


def test_06_ctrl_r_refreshes_or_documents_that_there_is_nothing_to_refresh():
    for name in ("NetTools", "DatabaseBrowser", "PodcastWindow"):
        s = src(WINDOWS[name])
        assert re.search(r"^    shortcutRefresh: win\.\w+", s, re.M), name
    for name in ("Dictionary", "Teleprompter"):
        s = src(WINDOWS[name])
        assert "Ctrl+R" in s and "N/A" in s, name
    # each bound refresh resolves to a real action in the same window
    assert "function refresh() { win.run(win.tool); }" in src(WINDOWS["NetTools"])
    assert 'function refresh() { Podcasts.run("list", []); }' in src(
        WINDOWS["PodcastWindow"]
    )
    # the Startup manager is Settings > Startup apps now
    assert "function refresh() {" in src(ROOT / "shani/Modules/Settings/SettingsStartup.qml")
    assert "function listTables() {" in src(WINDOWS["DatabaseBrowser"])


def test_07_header_actions_use_appwindows_tools_row_not_a_second_toolbar():
    for name, path in WINDOWS.items():
        s = src(path)
        assert s.count("\n    tools: [") <= 1, name  # one header row, never two
        assert not re.search(r"^\s*id: bar\b", s, re.M), name
    for name in (
        "Teleprompter",
        "NetTools",
        "DatabaseBrowser",
        "PodcastWindow",
    ):
        assert re.search(r"^    tools: \[", src(WINDOWS[name]), re.M), name
    # Dictionary has no header actions and uses AppWindow's body, not a second one
    assert not re.search(r"^\s*id: body\s*$", src(WINDOWS["Dictionary"]), re.M)


def test_08_list_rows_are_keyboard_reachable_not_only_their_iconbuttons():
    db = src(WINDOWS["DatabaseBrowser"])
    start = db.index("delegate: Rectangle {")
    delegate = db[start : db.index("EmptyState", start)]
    assert "KeyFocus" in delegate and "cellRow.Accessible.name" in delegate
    pod = src(WINDOWS["PodcastWindow"])
    assert "delegate: ListRow {" in pod
    assert "ListRow carries a KeyFocus" in pod
    assert "ListRow {" in src(WINDOWS["Dictionary"])
    assert "ListRow {" in src(WINDOWS["NetTools"])
    assert "SwitchRow {" in src(ROOT / "shani/Modules/Settings/SettingsStartup.qml")
    assert "KeyFocus { onActivated:" in src(RESTORE)


def test_09_settings_restore_panel_unwinds_and_refreshes_without_closing_the_host():
    s = src(RESTORE)
    assert 'Accessible.name: Tr.t("System restore")' in s
    assert "Qt.Key_Escape" in s and 'panel.confirming = ""' in s
    assert re.search(r"Qt\.Key_R\b", s)
    assert "SystemRestore.refresh()" in s
    # Ctrl+W is not bound here: it belongs to the hosting Settings AppWindow
    assert not re.search(r"Qt\.Key_W\b", s)
    assert "Ctrl+W" in s
