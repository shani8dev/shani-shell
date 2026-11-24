"""Static tests for the competitive research fixes (Terminal + Software).

Each test pins one behaviour a desktop terminal / software centre has that the
shipping ShaniOS windows did not. No QML runtime is available; these read the
source, like the sibling test_gap_* / test_software_* tests.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


TERM = "shani/Modules/Terminal/TerminalAppWindow.qml"
SOFT = "shani/Modules/Software/SoftwareWindow.qml"


def test_terminal_add_host_button_reaches_form():
    """Competitor: New/Add connection creates a host. The form existed with no caller."""
    s = read(TERM)
    assert 'Tr.t("Add host"); kind: "primary"' in s
    assert 'win.tab = "add";' in s
    # the button resets edit state so it cannot seed the form with an old host
    assert 'win.editId = "";' in s


def test_terminal_host_keyboard_navigation_and_search_shortcut():
    """Competitor: arrows + Enter walk/activate connections, '/' focuses search."""
    s = read(TERM)
    assert "Keys.onPressed: e => {" in s
    assert (
        "hostList.currentIndex = Math.min(hostList.count - 1, hostList.currentIndex + 1)"
        in s
    )
    assert "hostList.currentIndex = Math.max(0, hostList.currentIndex - 1)" in s
    assert "TerminalApp.connect(h)" in s
    assert "Qt.Key_Slash && hostSearch.visible" in s


def test_terminal_current_row_highlight_and_follow():
    """Competitor: the focused row is visibly selected and kept in view."""
    s = read(TERM)
    assert "hostList.currentItem === hostRow" in s
    assert "positionViewAtIndex(currentIndex, ListView.Contain)" in s


def test_terminal_copy_address_action():
    """Competitor: copy connection details to the clipboard from the host list."""
    s = read(TERM)
    assert 'icon: "edit-copy"; size: Theme.px(26); tip: Tr.t("Copy address")' in s
    assert "Quickshell.clipboardText = addr" in s


def test_software_installed_search_and_updates_filter():
    """Competitor: Discover filters the installed list by name and by updates."""
    s = read(SOFT)
    assert "property string installedQuery" in s
    assert "property bool updatesOnly" in s
    assert 'Tr.t("Find installed apps…")' in s
    assert 'Tr.t("Updates only")' in s
    assert "win.installedApps.filter(a =>" in s
    assert "(!win.updatesOnly || a.update)" in s
    assert "win.installedQuery.toLowerCase()" in s


def test_software_installed_empty_state():
    """Competitor: an explicit empty/no-match state instead of a blank list."""
    s = read(SOFT)
    assert "visible: ilist.count === 0" in s
    assert 'Tr.t("No apps match your filter")' in s
    assert 'Tr.t("No apps installed yet")' in s
