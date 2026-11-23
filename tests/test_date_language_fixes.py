"""Static checks for the date/language settings and DatePicker fixes."""

from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SETTINGS = ROOT / "shani/Modules/Settings/SettingsDateLanguage.qml"
PICKER = ROOT / "shani/Common/DatePicker.qml"


@pytest.fixture(scope="module")
def settings():
    return SETTINGS.read_text()


@pytest.fixture(scope="module")
def picker():
    return PICKER.read_text()


def test_preview_reruns_when_locale_changes(settings):
    assert "function refreshPreview()" in settings
    assert 'Proc.run("date-language-preview"' in settings
    # both a direct refresh and the file reload (after saving a new locale)
    assert settings.count("page.refreshPreview();") >= 2
    assert "id: sample" not in settings


def test_system_default_locale_can_be_chosen(settings):
    assert 'page.choosing === "" ? [] : [""].concat(' in settings
    assert 'selected: modelData === (page.choosing === "lang"' in settings


def test_logout_prompt_ignores_encoding_suffix(settings):
    assert '(Quickshell.env("LANG") || "").replace(/\\..*$/, "")' in settings
    assert 'page.lang.replace(/\\..*$/, "") !== page.langAtLogin' in settings


def test_custom_date_rejects_impossible_days(picker):
    assert "parsed.getFullYear() !== +m[1]" in picker
    assert "parsed.getDate() !== +m[3]" in picker
    assert "root.current = parsed;" in picker


def test_month_year_jump(picker):
    assert "Jump to month" in picker
    assert "root.current = new Date(+m[1], +m[2] - 1, 1);" in picker
