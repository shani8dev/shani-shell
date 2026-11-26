"""Background services keeps only its own two reads; the other sections moved."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def test_background_has_only_schedules_and_priority():
    page = read("shani/Modules/Settings/SettingsBackground.qml")
    assert 'v: "schedules"' in page and 'v: "priority"' in page
    for bad in (
        'v: "irq"',
        'v: "audit"',
        "PhoneTools",
        "SwitchRow",
        'page.obj("audit")',
        'page.obj("irq")',
    ):
        assert bad not in page, bad
    assert "Ui.backgroundServices = true" in page
    assert "PhoneTools.backgroundSet" not in page


def test_interrupts_moved_to_system_health():
    page = read("shani/Modules/Settings/SettingsSystemHealth.qml")
    assert '"system_background.py"' in page
    assert 'page.bgTool, "irq"' in page
    assert 'Tr.t("Interrupts")' in page
    assert "irq: { balanced:" in page
    assert "page.irq.cpus" in page


def test_audit_log_moved_to_security():
    page = read("shani/Modules/Settings/SettingsSecurity.qml")
    assert '"system_background.py"' in page
    assert 'page.bgTool, "audit"' in page
    assert 'Tr.t("Audit log records")' in page
    assert "log: page.auditLogRows.map" in page
    assert "page.auditLogRows" in page


def test_search_words_follow_the_sections():
    page = read("shani/Modules/Settings/SettingsPage.qml")

    def words(cat):
        import re

        match = re.search(r'id: "' + cat + r'", words: "([^"]*)"', page)
        assert match, cat
        return match.group(1)

    assert "irq" not in words("background") and "audit" not in words("background")
    assert "irq" in words("health")
    assert "audit" in words("security")

    index = read("shani/Modules/Settings/SettingsIndex.js")
    for key, cat in (("interrupts", "health"), ("auditLog", "security")):
        line = next(l for l in index.splitlines() if 'key: "' + key + '"' in l)
        assert 'cat: "' + cat + '"' in line, (key, line)
