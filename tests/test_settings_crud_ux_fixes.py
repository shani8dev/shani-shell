"""Static checks for the CRUD-pages UX fixes: confirmations, inline validation,
and visible save/status feedback.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def src(name: str) -> str:
    return (ROOT / "shani/Modules/Settings" / name).read_text(encoding="utf-8")


def test_destructive_actions_need_a_second_click():
    net = src("SettingsNetwork.qml")
    assert "ConfirmButton {" in net
    assert 'Tr.t("Tap again to forget")' in net
    assert 'forgetConfirm.armed ? "danger" : "plain"' in net

    security = src("SettingsSecurity.qml")
    assert 'property string confirmingAudit: ""' in security
    assert 'Tr.t("Tap again to remove rules")' in security

    journal = src("SettingsJournal.qml")
    assert 'property string confirmingStorage: ""' in journal
    assert 'Tr.t("Tap again to stop storing")' in journal

    date = src("SettingsDateLanguage.qml")
    assert "ConfirmButton {" in date
    assert 'Tr.t("Tap again for everyone")' in date


def test_invalid_values_explain_why_save_is_disabled():
    security = src("SettingsSecurity.qml")
    assert "error: page.wholeNumberError(minlen)" in security
    assert "enabled: !page.pwBusy && page.pwValid" in security

    modules = src("SettingsModules.qml")
    assert 'Tr.t("Use a new name: letters, numbers, - or _")' in modules
    assert 'Tr.t("Use a whole number")' in modules

    journal = src("SettingsJournal.qml")
    assert "enabled: !page.busy && page.policyValid" in journal
    assert 'Tr.t("Use a size like 500M or 2G")' in journal

    sharing = src("SettingsSharing.qml")
    assert 'Tr.t("At least 4 characters")' in sharing


def test_status_and_empty_states_are_explicit():
    security = src("SettingsSecurity.qml")
    assert 'Tr.t("The kernel did not report its security modules")' in security
    assert (
        'Button { text: Tr.t("Retry"); onClicked: SecurityInfo.refresh() }' in security
    )

    sharing = src("SettingsSharing.qml")
    assert "visible: !Cast.available" in sharing
    assert 'Tr.t("Casting is not available on this computer.")' in sharing

    for name in (
        "SettingsJournal.qml",
        "SettingsModules.qml",
        "SettingsPrinters.qml",
        "SettingsSharing.qml",
    ):
        text = src(name)
        assert "InfoBanner {" in text, name
        assert 'tone: page.noteOk ? "ok" : "error"' in text, name

    printers = src("SettingsPrinters.qml")
    assert 'Tr.t("Finds printers announced on your local network")' in printers
    assert 'Tr.t("Your defaults for this printer")' in printers
