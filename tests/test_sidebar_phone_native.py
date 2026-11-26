"""Quick Settings' phone details connect Android with what the phone has built in."""

from pathlib import Path

SERVICE = Path("shani/Modules/ControlCenter/SidebarDetails.qml")


def source(path):
    return Path(path).read_text(encoding="utf-8")


def test_no_phone_app_words():
    s = source(SERVICE)
    for banned in ("KDE Connect", "kdeconnect", "GSConnect", "gsconnect"):
        assert banned not in s, banned


def test_bluetooth_and_wifi_pairing_choices():
    s = source(SERVICE)
    assert 'Tr.t("Bluetooth")' in s and 'Tr.t("Wi-Fi debugging")' in s
    assert 'Devices.connect("bluetooth", modelData.address)' in s
    assert (
        'Devices.connect("android", phoneDetails.pairAddress.trim(), phoneDetails.pairCode.trim())'
        in s
    )
    assert "Bluetooth.devices.values" in s


def test_phone_list_comes_from_the_link_service():
    s = source(SERVICE)
    assert "model: Link.devices" in s
    assert "Phone.devices" not in s
    assert "Phone.pair(" not in s and "Phone.unpair(" not in s
    assert "Phone.ring(" not in s and "Phone.sendClipboard(" not in s


def test_no_claim_of_a_phone_app():
    s = source(SERVICE)
    assert "Nothing to install on it." in s
    assert "No phone found. Open" not in s


def test_common_components_and_accessible_names():
    s = source(SERVICE)
    for component in (
        "Picks",
        "ListRow",
        "EmptyState",
        "SettingsSection",
        "BusyNote",
        "Button",
    ):
        assert component + " {" in s, component
    assert "Accessible.name" in s
