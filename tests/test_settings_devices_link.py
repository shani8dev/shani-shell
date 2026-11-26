"""Settings > Devices is a door to one Devices app, not a second device UI."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def test_settings_page_has_no_device_logic():
    page = read("shani/Modules/Settings/SettingsDevices.qml")
    for bad in (
        "Devices.connect(",
        "Devices.fm(",
        "Devices.nfc(",
        "Devices.ir(",
        "AndroidTools.",
        "Link.devices",
        "PhoneTools.",
        "TextField",
        "BusyNote",
    ):
        assert bad not in page, bad
    assert "Ui.devicesTab" in page
    assert "Ui.devices = true" in page
    assert page.count("onClicked: page.open(") == 3  # phones, screen, gadgets


def test_the_app_owns_the_tab_and_search_points_to_it():
    window = read("shani/Modules/Devices/DevicesWindow.qml")
    assert "win.tab = Ui.devicesTab" in window
    assert 'Ui.devicesTab = ""' in window
    assert "property string devicesTab" in read("shani/Common/Ui.qml")

    index = read("shani/Modules/Settings/SettingsIndex.js")
    assert 'key: "devicesApp"' in index and 'linkTab: "phones"' in index
    # the other device words land on this page, whose rows open the app's tabs
    for key in ("fmRadio", "nfcReader", "screenOnPhone"):
        line = next(l for l in index.splitlines() if 'key: "' + key + '"' in l)
        assert 'cat: "devices"' in line, (key, line)

    page = read("shani/Modules/Settings/SettingsPage.qml")
    assert "Ui.devicesTab = entry.linkTab" in page
