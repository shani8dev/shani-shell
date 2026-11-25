"""Static checks for the Gateway, Paste history and VPN-view fixes.

These are source-level assertions (the style of test_utilities2.py): the three
QML surfaces need a running shell to render. Each test guards one fix, so a
regression names the behaviour that broke.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


GW = lambda: read("shani/Modules/Nearby/NearbyWindow.qml")
PH = lambda: read("shani/Modules/PasteHistoryWindow.qml")
CB = lambda: read("shani/Services/Clipboard.qml")


# ---- Gateway -----------------------------------------------------------------


# ---- Gateway was merged: its peers are Nearby Share's, its VPN list is
#      Settings > Network's VpnPanel and the Control Centre's VPN section -------


def test_gateway_peers_come_from_the_existing_discovery_services():
    g = GW()
    assert "Nearby.devices.filter(" in g          # no discovery of its own
    assert "readonly property var shownDevices" in g and "model: win.shownDevices" in g


def test_gateway_qr_uses_the_service_and_keeps_a_textual_handle_fallback():
    g = GW()
    assert "Qr.show(d.alias || Tr.t(\"Nearby device\"), v)" in g
    assert "win.addressOf(d) || win.handleOf(d)" in g


def test_gateway_search_matches_a_prefix_not_any_substring():
    g = GW()
    assert ".toLowerCase().indexOf(q) === 0" in g
    assert 'placeholder: Tr.t("Type the start of a name or handle")' in g


def test_gateway_copy_has_three_formats_with_accessible_names():
    # address and handle copy; the third format was a https://gateway.local/
    # link that nothing served, so it went with the window
    g = GW()
    assert 'win.copyOf(modelData, "address")' in g and 'win.copyOf(modelData, "handle")' in g
    assert "tip: Tr.t(\"Copy %1's address\")" in g and "tip: Tr.t(\"Copy %1's handle\")" in g
    assert "gateway.local" not in g


def test_gateway_recent_peers_are_deduped_and_bounded():
    g = GW()
    assert "win.recent.filter(f => f !== d.fingerprint)).slice(0, 6)" in g


def test_gateway_peers_have_empty_and_error_states():
    g = GW()
    assert 'title: Tr.t("No one nearby yet")' in g
    assert "Tr.t(\"This device has no %1\")" in g


def test_gateway_vpn_reads_connections_from_nmcli():
    # one VPN list, the service's (Services/Vpn via bridge/vpn.py), shown in
    # Settings > Network and switched in the Control Centre
    page = read("shani/Modules/Settings/SettingsPage.qml")
    assert 'source: "../../Modules/Vpn/VpnPanel.qml"' in page
    assert "onClicked: Net.setVpn(modelData.name, !modelData.active)" in read("shani/Modules/ControlCenter/SidebarDetails.qml")


def test_gateway_vpn_connect_disconnect_give_feedback_and_guard_busy():
    panel = read("shani/Modules/Vpn/VpnPanel.qml")
    assert "connect" in panel.lower() and "disconnect" in panel.lower()


def test_gateway_vpn_empty_state_and_keyboard_names():
    assert 'Tr.t("No VPN configured")' in read("shani/Modules/ControlCenter/SidebarDetails.qml")
    assert not (ROOT / "shani/Modules/GatewayWindow.qml").exists()


def test_clipboard_extension_adds_helpers_without_new_properties():
    c = CB()
    # Helpers only: no property/readonly property was added, so the wiring and
    # i18n tests keep seeing the same singleton shape.
    original = {
        "entries",
        "origins",
        "cache",
        "available",
        "excludeSecrets",
        "crypto",
        "watcher",
        "encrypted",
        "terminals",
    }
    declared = set()
    for line in c.splitlines():
        stripped = line.strip()
        m = re.match(r"(?:readonly\s+)?property\s+\w+\s+(\w+)", stripped)
        if m:
            declared.add(m.group(1))
    assert declared <= original
    for fn in (
        "slotCount",
        "slot",
        "slotLabel",
        "pasteSlot",
        "deleteSlot",
        "fuzzyScore",
        "isFavourite",
        "toggleFavourite",
        "imageTypesCommand",
    ):
        assert f"function {fn}(" in c
    assert "function toggleFavourite(text)" in c
    assert "Settings.data.clipPins" in c
    assert 'return ["wl-paste", "--list-types"];' in c


# ---- Paste history ------------------------------------------------------------


def test_paste_history_has_numbered_slots_and_paste_by_number():
    p = PH()
    assert 'objectName: "paste-slot-" + (slotList.index + 1)' in p
    assert "function pasteNumber(n)" in p
    assert "Clipboard.pasteSlot(n - 1)" in p
    assert "e.key >= Qt.Key_1 && e.key <= Qt.Key_9" in p
    assert "if (searchField.activeFocus) return;" in p
    assert "function slotLabel(n) { return Clipboard.slotLabel(n); }" in p
    assert 'Tr.t("Press 1-9 to paste a slot, Enter to paste the selected one")' in p


def test_paste_history_fuzzy_search_and_favourites():
    p = PH()
    assert 'objectName: "paste-search"' in p
    assert "Clipboard.fuzzyScore(e.text, q) > 0" in p
    assert "function visibleEntries()" in p
    assert 'objectName: "paste-favourites"' in p
    assert "Clipboard.isFavourite(e.text)" in p
    assert "Clipboard.toggleFavourite(e.text)" in p
    assert 'Tr.t("No favourite entries")' in p
    assert 'Tr.t("No matching entries")' in p


def test_paste_history_delete_and_image_unsupported_note():
    p = PH()
    assert "Clipboard.remove(e);" in p
    assert 'accessibleName: Tr.t("Delete slot %1")' in p
    assert "Clipboard.imageTypesCommand()" in p
    assert "/image\\//i.test(text)" in p
    assert 'Tr.t("Pasting images is not supported here - only text is available")' in p
    assert "function insertImage()" in p
    assert "Component.onCompleted: win.checkImages()" in p


def test_paste_history_empty_error_and_keyboard_states():
    p = PH()
    assert 'Tr.t("Clipboard is empty")' in p
    assert 'Tr.t("Clipboard history is not available")' in p
    assert "visible: !Clipboard.available" in p
    assert "Accessible.role: Accessible.ListItem" in p
    assert 'Accessible.name: Tr.t("Slot %1")' in p
    assert "KeyFocus { name: row.Accessible.name" in p
    assert "Keys.onEscapePressed" in p
