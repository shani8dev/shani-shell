"""Static checks for the five two-tap confirms moved onto shani/Common/ConfirmButton.qml.

Each test owns one site: the old hand-rolled confirming flag, timer and label flip
must be gone, and the destructive action must live in onConfirmed.
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


def test_network_forget_uses_confirm_button():
    s = read("shani/Modules/Settings/SettingsNetwork.qml")
    b = confirm_block(s, "forgetConfirm")
    assert 'text: Tr.t("Forget")' in b
    assert 'armedText: Tr.t("Tap again to forget")' in b
    assert 'kind: forgetConfirm.armed ? "danger" : "plain"' in b
    assert "interval: 4000" in b
    assert 'onConfirmed: page.modify(net.modelData.uuid, ["delete"])' in b
    # the per-network accessible name survived the migration
    assert 'Accessible.name: text + " " + (net.modelData.name' in b
    assert "confirmingForget" not in s and "forgetTimer" not in s


def test_printer_remove_uses_confirm_button():
    s = read("shani/Modules/Settings/SettingsPrinters.qml")
    b = confirm_block(s, "removePrinter")
    assert 'text: Tr.t("Remove…")' in b
    assert 'armedText: Tr.t("Tap again to remove")' in b
    assert 'kind: "danger"' in b
    assert "interval: 3000" in b
    assert 'onConfirmed: page.run(["pkexec", "lpadmin", "-x", pr.modelData.name]' in b
    assert "pr.confirming" not in s and "Timer { interval: 3000" not in s


def test_system_locale_reset_uses_confirm_button():
    s = read("shani/Modules/Settings/SettingsDateLanguage.qml")
    b = confirm_block(s, "resetLanguage")
    assert 'text: Tr.t("Use for everyone and the login screen")' in b
    assert 'armedText: Tr.t("Tap again for everyone")' in b
    assert 'kind: resetLanguage.armed ? "danger" : "plain"' in b
    assert "interval: 4000" in b
    assert '"localectl", "set-locale", "LANG=" + page.lang' in b
    assert "systemLocale.running = true" in b
    assert "confirmingSystemLocale" not in s and "systemLocaleConfirmTimer" not in s


def test_overview_close_all_uses_confirm_button():
    s = read("shani/Modules/Overview/OverviewStats.qml")
    b = confirm_block(s, "closeAllConfirm")
    assert 'text: Tr.t("Close all windows")' in b
    assert 'armedText: Tr.t("Close %1 windows — click again", win.windows.length)' in b
    assert "interval: 4000" in b
    assert 'Niri.action("close-window", "--id", w.id)' in b
    # hiding the card disarms the two-tap state instead of resetting a flag
    assert "closeAllConfirm.disarm()" in s
    assert "win.confirming" not in s and "unconfirm" not in s


def test_update_all_uses_confirm_button():
    s = read("shani/Modules/Software/SoftwareWindow.qml")
    b = confirm_block(s, "updateAllConfirm")
    assert 'text: Tr.t("Update all")' in b
    assert 'armedText: Tr.t("Click again to update all")' in b
    assert "interval: 4000" in b
    assert "enabled: !jobProc.running" in b
    assert 'win.runJob(["update-all"], "all")' in b and "onConfirmed:" in b
    assert "visible: updateAllConfirm.armed && win.updates > 0" in s
    # both tab-switch paths disarm the button
    assert s.count("updateAllConfirm.disarm()") == 2
    assert "confirmUpdateAll" not in s and "confirmTimer" not in s
