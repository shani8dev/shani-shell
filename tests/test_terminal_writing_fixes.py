"""Static checks for concrete gaps in the Terminal and Writing tools windows."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TERMINAL = "shani/Modules/Terminal/TerminalAppWindow.qml"
WRITING = "shani/Modules/WritingTools/WritingToolsSheet.qml"


def read(path):
    return (ROOT / path).read_text()


def test_edit_id_is_a_declared_property():
    """editId was read and written six times but never declared, so the
    'Add host'/'Save' label binding saw undefined and never said 'Add host'."""
    s = read(TERMINAL)
    assert 'property string editId: ""' in s
    assert s.index('property string editId: ""') < s.index("win.editId = h.id")


def test_cancel_clears_the_host_form():
    """Cancelling an edit left the old host's fields behind, so the next
    'Add host' opened pre-filled with another host's data."""
    s = read(TERMINAL)
    start = s.index('text: Tr.t("Cancel")')
    cancel = s[start : s.index("            }", start)]
    for field in (
        "newHostName",
        "newHostAddr",
        "newHostUser",
        "newHostPort",
        "newHostKey",
        "newHostProxyJump",
        "newHostExtraOpts",
    ):
        assert 'win.%s = ""' % field in cancel
    assert "win.newHostForwardAgent = false" in cancel
    assert 'win.editId = ""' in cancel


def test_empty_state_knows_a_search_matches_nothing():
    """With hosts present but a filter matching none, the list claimed there
    were no SSH hosts yet and told the person to add one."""
    s = read(TERMINAL)
    assert 'TerminalApp.hosts.length === 0 ? Tr.t("No SSH hosts yet")' in s
    assert 'Tr.t("No hosts match your search")' in s
    assert 'Tr.t("Try a different name, address or user.")' in s


def test_failed_write_keeps_its_action_row():
    """On error the result row vanished entirely, taking 'Try again' with it."""
    s = read(WRITING)
    assert 'visible: WritingTools.result !== "" || WritingTools.error !== ""' in s
    assert (
        "enabled: !!WritingTools.lastInstruction; onClicked: WritingTools.again()" in s
    )
    assert "enabled: !!WritingTools.result; onClicked: WritingTools.copy()" in s
    assert "enabled: !!WritingTools.result; onClicked: WritingTools.replace()" in s


def test_custom_instruction_does_not_go_stale():
    """A typed instruction survived both a run and a close/reopen of the sheet."""
    s = read(WRITING)
    assert 'WritingTools.run(text.trim(), text.trim()); text = ""' in s
    assert 'onVisibleChanged: if (!visible) text = ""' in s
