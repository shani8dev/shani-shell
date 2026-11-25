"""Round-2 static checks: the remaining safe two-tap confirms use ConfirmButton.

Each migrated site must have lost its hand-rolled flag, timer and label flip.
Keyed confirms carry the stable key in ConfirmButton's `value` property (`id`
is a reserved QML attribute). Unsafe sites are documented, not migrated.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def confirm_block(text, ident):
    """The ConfirmButton {...} block carrying `ident`."""
    start = text.index("id: " + ident)
    open_brace = text.index("{", text.rfind("ConfirmButton", 0, start))
    depth = 0
    for i in range(open_brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace : i + 1]
    raise AssertionError("unterminated ConfirmButton block for " + ident)


def test_privacy_recent_uses_confirm_button():
    s = read("shani/Modules/Settings/SettingsPrivacy.qml")
    b = confirm_block(s, "clearRecentConfirm")
    assert 'text: Tr.t("Clear the recent files list")' in b
    assert 'armedText: Tr.t("Tap again to clear the recent files list")' in b
    assert 'kind: clearRecentConfirm.armed ? "danger" : "plain"' in b
    assert "interval: 4000" in b
    assert "onConfirmed: Housekeeping.clearRecent()" in b


def test_privacy_trash_uses_confirm_button():
    s = read("shani/Modules/Settings/SettingsPrivacy.qml")
    b = confirm_block(s, "emptyTrashConfirm")
    assert 'text: Tr.t("Empty the trash now")' in b
    assert 'armedText: Tr.t("Tap again to empty the trash")' in b
    assert "interval: 4000" in b
    assert "onConfirmed: Housekeeping.emptyTrash()" in b


def test_privacy_clipboard_uses_confirm_button():
    s = read("shani/Modules/Settings/SettingsPrivacy.qml")
    b = confirm_block(s, "clearClipboardConfirm")
    assert 'text: Tr.t("Clear clipboard history")' in b
    assert 'armedText: Tr.t("Tap again to clear clipboard history")' in b
    assert "interval: 4000" in b
    assert "onConfirmed: Clipboard.wipe()" in b


def test_privacy_no_hand_rolled_flag_and_hide_disarms():
    s = read("shani/Modules/Settings/SettingsPrivacy.qml")
    assert "page.confirming" not in s
    assert "confirmThen" not in s
    assert "Timer {" not in s
    for ident in ("clearRecentConfirm", "emptyTrashConfirm", "clearClipboardConfirm"):
        assert ident + ".disarm()" in s
        assert "visible: " + ident + ".armed" in s  # Cancel follows the armed state


def test_window_layout_delete_uses_confirm_button():
    s = read("shani/Modules/WindowLayouts/WindowLayouts.qml")
    b = confirm_block(s, "deleteLayoutConfirm")
    assert "value: String(modelData.id)" in b
    assert 'text: Tr.t("Delete")' in b
    assert 'armedText: Tr.t("Click again to delete")' in b
    assert "interval: 3000" in b
    assert "onConfirmed: WindowLayouts.removeCustom(modelData.id)" in b
    # the old tip fed AT; the exact name survives in both states
    assert (
        'Accessible.name: deleteLayoutConfirm.armed ? Tr.t("Click again to delete") : Tr.t("Delete layout")'
        in b
    )
    assert "pendingDeleteId" not in s and "pendingDeleteTimer" not in s
    assert "deleteLayoutConfirm.disarm()" in s  # hiding the palette cancels


def test_cron_confirm_carries_its_key():
    s = read("shani/Modules/Services/ServicesWindow.qml")
    b = confirm_block(s, "cronRemoveConfirm")
    assert "value: String(modelData.index)" in b
    assert "onConfirmed: SysServices.cronRemove(modelData.index)" in b


def test_process_end_uses_confirm_button_keyed_by_pid():
    s = read("shani/Modules/Processes/Processes.qml")
    b = confirm_block(s, "endConfirm")
    assert "value: String(procRow.p.pid)" in b
    assert 'text: Tr.t("End")' in b
    assert 'armedText: Tr.t("Tap again")' in b
    assert "interval: 3000" in b
    assert "TopProcesses.end(procRow.p.pid, win.endSignal)" in b
    assert 'Accessible.name: Tr.t("End") + " " + procRow.p.name' in b
    # a recycled delegate must not retarget the second tap
    assert "onArmedChanged: if (armed) armedPid = procRow.p.pid" in b
    assert "endConfirm.armedPid === procRow.p.pid" in b
    assert "confirmPid" not in s and "endConfirmTimer" not in s


def test_process_end_disarms_on_refresh_and_hide():
    s = read("shani/Modules/Processes/Processes.qml")
    b = confirm_block(s, "endConfirm")
    assert b.count("endConfirm.disarm()") == 2  # refresh drops pid, window hides


def test_settings_modules_skip_is_documented():
    s = read("shani/Modules/Settings/SettingsModules.qml")
    # no two-tap confirm exists here; the index-keyed Remove buttons are unsafe
    assert "shortcut:" in s
    assert "list index" in s
    assert "ConfirmButton" not in s
