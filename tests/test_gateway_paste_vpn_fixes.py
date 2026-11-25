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


GW = lambda: read("shani/Modules/GatewayWindow.qml")
PH = lambda: read("shani/Modules/PasteHistoryWindow.qml")
CB = lambda: read("shani/Services/Clipboard.qml")


# ---- Gateway -----------------------------------------------------------------


def test_gateway_peers_come_from_the_existing_discovery_services():
    g = GW()
    # The window has no discovery engine of its own: it reads what Nearby and
    # the phone service already know, and degrades to an empty list.
    assert 'typeof Nearby !== "undefined"' in g
    assert "Nearby.devices" in g
    assert "Phone.reachable" in g
    assert "function peerObjects()" in g
    assert "function refreshPeers()" in g
    assert "function onDevicesChanged()" in g


def test_gateway_qr_uses_the_service_and_keeps_a_textual_handle_fallback():
    g = GW()
    assert 'typeof Qr !== "undefined" && Qr && typeof Qr.show === "function"' in g
    assert "Qr.show(p.name, text)" in g
    # When Qr is absent the handle is still on screen, with an honest reason.
    assert 'objectName: "peer-handle"' in g
    assert "QR is unavailable - share the handle instead" in g
    assert "return false;" in g
    assert "function showQr(p)" in g


def test_gateway_search_matches_a_prefix_not_any_substring():
    g = GW()
    assert 'objectName: "gateway-search"' in g
    assert "function matchingPeers(q)" in g
    assert "String(p.name).toLowerCase().indexOf(s) === 0" in g
    assert "String(p.handle).toLowerCase().indexOf(s) === 0" in g
    assert "model: win.matchingPeers(win.search)" in g
    assert 'Tr.t("No peers match that prefix")' in g


def test_gateway_copy_has_three_formats_with_accessible_names():
    g = GW()
    assert 'readonly property var formats: ["handle", "link", "address"]' in g
    assert "function peerFormats(p)" in g
    assert '"https://gateway.local/peer/" + encodeURIComponent(p.handle)' in g
    assert "Quickshell.clipboardText = v;" in g
    assert "win.copyPeer(row.modelData, modelData)" in g
    assert 'Tr.t("Copy %1 of %2")' in g
    assert "KeyFocus { name: parent.Accessible.name" in g


def test_gateway_recent_peers_are_deduped_and_bounded():
    g = GW()
    assert "function noteRecent(p)" in g
    assert "win.recent.filter(x => x.id !== p.id)" in g
    assert ".slice(0, 6)" in g
    assert 'Tr.t("Recent peers")' in g
    assert 'win.copyPeer(modelData, "handle")' in g


def test_gateway_peers_have_empty_and_error_states():
    g = GW()
    assert 'Tr.t("No peers found")' in g
    assert (
        'onAction: { if (typeof Nearby !== "undefined" && Nearby) Nearby.scan();' in g
    )
    assert 'Tr.t("Peers could not be loaded")' in g
    assert "color: Theme.danger; wrapMode: Text.WordWrap" in g
    assert 'visible: win.peerError !== ""' in g


def test_gateway_vpn_reads_connections_from_nmcli():
    g = GW()
    assert (
        'command: ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show"]' in g
    )
    assert "/vpn|wireguard|tunnel|openvpn/i.test(c.kind)" in g
    assert 'win.connections = text.split("\\n")' in g
    assert "stderr: StdioCollector { id: vpnListErr }" in g
    assert 'Tr.t("Could not read VPN connections")' in g
    assert "win.flashVpn(" in g


def test_gateway_vpn_connect_disconnect_give_feedback_and_guard_busy():
    g = GW()
    assert '["nmcli", "connection", vpnAction.up ? "up" : "down", c.name]' in g
    assert 'Tr.t("Connected to %1").arg(vpnAction.name)' in g
    assert 'Tr.t("Disconnected from %1").arg(vpnAction.name)' in g
    assert 'Tr.t("Could not change %1")' in g
    assert "enabled: !win.vpnBusy" in g
    assert "win.refreshVpn();" in g


def test_gateway_vpn_empty_state_and_keyboard_names():
    g = GW()
    assert 'Tr.t("No VPN connections")' in g
    assert 'icon: "network-vpn"' in g
    assert 'Tr.t("Connect")' in g and 'Tr.t("Disconnect")' in g
    assert (
        'Accessible.name: modelData.name + ", " + win.vpnStateText(modelData.state)'
        in g
    )
    assert "KeyFocus { name: parent.Accessible.name" in g
    assert "Keys.onEscapePressed" in g


# ---- Clipboard service extension ---------------------------------------------


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
