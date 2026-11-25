"""Static checks for the reusable UI components and shared tool catalog."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shani/Common"
BUSY = (COMMON / "BusyNote.qml").read_text()
CONFIRM = (COMMON / "ConfirmButton.qml").read_text()
TOOLS = (COMMON / "Tools.js").read_text()
UI = (ROOT / "shani/Common/Ui.qml").read_text()


def test_busy_note_wraps_spinner_and_note_with_at_name():
    assert "Spinner {" in BUSY
    assert "text: root.note" in BUSY
    assert "Accessible.role: Accessible.StatusBar" in BUSY
    assert "Accessible.name: root.note" in BUSY


def test_confirm_button_owns_flag_timer_and_disarm():
    assert "property bool armed: false" in CONFIRM
    assert "Timer { id: timer; interval: root.interval" in CONFIRM
    assert "function disarm()" in CONFIRM
    assert "signal confirmed(string id)" in CONFIRM


def test_confirm_button_kinds_match_button():
    assert 'root.danger ? "danger"' in CONFIRM
    assert '"outline"' in CONFIRM
    assert '"plain"' in CONFIRM


def test_tools_catalog_declares_all_nine_tools():
    for flag in (
        "dictionary",
        "podcasts",
        "teleprompter",
        "netTools",
        "databaseBrowser",
        "startupManager",
        "nearby",
        "pasteHistory",
        "scheduled",
    ):
        assert f'flag: "{flag}"' in TOOLS
        assert f'op: "{flag}Open"' in TOOLS or f'op: "{flag[:-4]}Open"' in TOOLS


def test_tools_entries_carry_label_icon_and_tool_keyword():
    for line in TOOLS.splitlines():
        if "label:" in line:
            assert "icon:" in line and '"tool ' in line


def test_close_apps_resets_every_new_flag():
    for flag in (
        "dictionary",
        "podcasts",
        "teleprompter",
        "netTools",
        "databaseBrowser",
        "nearby",
        "pasteHistory",
        "irc",
        "health",
        "cloudSync",
        "servicesApp",
        "settingsOpen",
    ):
        assert f"{flag} = false;" in UI
