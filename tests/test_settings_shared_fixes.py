"""Static checks for the shared Settings scaffolding.

SettingsSection (title + optional hint + rows) and SettingRow (icon + title +
subtitle + trailing control, with the ListRow accessibility wiring) replace the
repeated SectionTitle / ListRow blocks the Settings pages each carried. Nothing
here starts the shell; it only reads the QML and asserts the components exist,
expose their contract, and are adopted with labels and actions preserved.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shani/Common"
MODULES = ROOT / "shani/Modules/Settings"

SECTION = COMMON / "SettingsSection.qml"
ROW = COMMON / "SettingRow.qml"

PAGES = {
    "SettingsPrivacy": MODULES / "SettingsPrivacy.qml",
    "SettingsStorage": MODULES / "SettingsStorage.qml",
    "SettingsSound": MODULES / "SettingsSound.qml",
    "SettingsNetwork": MODULES / "SettingsNetwork.qml",
}


def source(path):
    return Path(path).read_text(encoding="utf-8")


def test_settingssection_contract():
    s = source(SECTION)
    assert "ColumnLayout" in s
    assert "property string title" in s
    assert "property string hint" in s
    assert "SectionTitle" in s  # the title it wraps
    assert "Theme.px(12)" in s  # default spacing
    assert "Layout.fillWidth: true" in s


def test_settingrow_contract():
    s = source(ROW)
    assert "ListRow" in s  # the common row it builds on
    assert "property alias control" in s  # the named trailing-control slot
    # ListRow carries the icon/title/subtitle/selected/interactive + AT wiring
    assert "Accessible" in source(COMMON / "ListRow.qml")


def test_pages_adopt_shared_components():
    for name, path in PAGES.items():
        s = source(path)
        assert "SettingsSection" in s or "SettingRow" in s, name


def test_privacy_labels_and_actions_preserved():
    s = source(PAGES["SettingsPrivacy"])
    assert "SettingRow" in s  # the grants list adopted it
    for label in [
        "Lock screen",
        "Recent files",
        "Trash",
        "Clipboard",
        "What apps may use",
        "Location services",
    ]:
        assert 'Tr.t("%s")' % label in s, label
    # the revoke action is unchanged
    assert '"permission-remove"' in s
    assert "Housekeeping.clearRecent()" in s
    assert "Housekeeping.emptyTrash()" in s


def test_network_labels_and_actions_preserved():
    s = source(PAGES["SettingsNetwork"])
    assert "SettingRow" in s  # the DNS list adopted it
    assert "SettingsSection" in s
    for label in ["Privacy & power", "Hotspot", "Bluetooth"]:
        assert 'Tr.t("%s")' % label in s, label
    assert "page.useDns(modelData.value)" in s  # DNS pick still applies
    assert "Net.setMacRandom(on)" in s


def test_sound_labels_preserved():
    s = source(PAGES["SettingsSound"])
    assert "SettingsSection" in s
    for label in ["Sound effects", "Microphone"]:
        assert 'Tr.t("%s")' % label in s, label
    assert "page.d.fxEnabled = on" in s
    assert "page.d.micNoise = on" in s


def test_storage_labels_preserved():
    s = source(PAGES["SettingsStorage"])
    assert "SettingsSection" in s
    for label in ["SSD maintenance", "App caches"]:
        assert 'Tr.t("%s")' % label in s, label
    assert '"fstrim-set"' in s
    assert 'page.confirmThen("cache:"' in s
