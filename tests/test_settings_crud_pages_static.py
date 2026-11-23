"""Static sanity for the settings pages touched by recent CRUD ports.

These are light checks that catch obvious QML mistakes (missing expected
structure, accidental ComboBox use, duplicate active plumbing). Generic QML
invariants already live in test_qml_static.py; this file is page-specific.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PAGES = [
    ROOT / "shani/Modules/Settings/SettingsJournal.qml",
    ROOT / "shani/Modules/Settings/SettingsSecurity.qml",
    ROOT / "shani/Modules/Settings/SettingsModules.qml",
    ROOT / "shani/Modules/Settings/SettingsDateLanguage.qml",
    ROOT / "shani/Modules/Settings/SettingsSharing.qml",
]


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_crud_settings_pages_exist():
    missing = [str(p.relative_to(ROOT)) for p in PAGES if not p.exists()]
    assert not missing, f"missing pages: {missing}"


def test_crud_settings_pages_have_active_property():
    for p in PAGES:
        text = _read(p)
        assert "property bool active" in text, f"{p.name}: missing active property"


def test_crud_settings_pages_import_common():
    for p in PAGES:
        text = _read(p)
        assert "import qs.Common" in text, f"{p.name}: missing qs.Common import"


def test_crud_settings_pages_do_not_use_combobox():
    for p in PAGES:
        text = _read(p)
        # ComboBox needs QtQuick.Controls ComboBox styling in this shell; these
        # pages use Choice/Button/TextField patterns instead.
        assert "ComboBox" not in text, f"{p.name}: unexpected ComboBox use"


def test_crud_settings_pages_have_section_title():
    for p in PAGES:
        text = _read(p)
        assert "SectionTitle" in text, f"{p.name}: missing SectionTitle"


def test_journal_page_has_journald_crud_hooks():
    text = _read(ROOT / "shani/Modules/Settings/SettingsJournal.qml")
    for needle in ["journald-set", "journald-vacuum", "SystemMaxUse", "Storage"]:
        assert needle in text, f"SettingsJournal.qml missing {needle}"


def test_security_page_has_security_crud_hooks():
    text = _read(ROOT / "shani/Modules/Settings/SettingsSecurity.qml")
    for needle in ["pwquality-set", "hosts-set", "sudoers-set", "apparmor-set"]:
        assert needle in text, f"SettingsSecurity.qml missing {needle}"


def test_modules_page_has_modules_crud_hooks():
    text = _read(ROOT / "shani/Modules/Settings/SettingsModules.qml")
    for needle in ["modprobe-blacklist-set", "modules-load-set", "sysctl-set"]:
        assert needle in text, f"SettingsModules.qml missing {needle}"


def test_date_language_page_has_ntp_hook():
    text = _read(ROOT / "shani/Modules/Settings/SettingsDateLanguage.qml")
    for needle in ["timesyncd-set", "NTP", "FallbackNTP"]:
        assert needle in text, f"SettingsDateLanguage.qml missing {needle}"


def test_sharing_page_has_remote_access_hook():
    text = _read(ROOT / "shani/Modules/Settings/SettingsSharing.qml")
    for needle in ["remote-access-set", "PasswordAuthentication", "PermitRootLogin"]:
        assert needle in text, f"SettingsSharing.qml missing {needle}"
