"""Static regressions for the pass-21 screen-sharing / phone-link fixes.

QML cannot run under pytest here, so these assert the bindings that carry each
fix: no implicit Bluetooth discoverability, per-device charging text, an
in-shell Sunshine PIN instead of xdg-open, and a cast session with a Stop.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_bluetooth_discoverable_is_an_explicit_2_minute_toggle():
    """Fix 1: the open-panel implicit discoverable bind is gone; a toggle + timer owns it."""
    sidebar = source("shani/Modules/ControlCenter/SidebarDetails.qml")

    assert "sidebar.bt.discoverable = visible && sidebar.bt.enabled" not in sidebar
    assert "property bool discoverWanted: false" in sidebar
    assert "property int discoverLeft: 0" in sidebar
    assert "discoverLeft = on ? 120 : 0" in sidebar
    assert 'text: Tr.t("Discoverable for 2 minutes")' in sidebar
    assert "id: discoverTimer" in sidebar and "interval: 1000" in sidebar
    assert "discoverLeft--;" in sidebar
    # the countdown turns it back off, it is not left on for the whole session
    assert "sidebar.bt.discoverable = false;" in sidebar
    assert "onToggled: on => setDiscoverable(on)" in sidebar


def test_phone_rows_show_charge_and_charging():
    """Fix 2: the bridge's charging flag is rendered, not dropped."""
    phone = source("shani/Services/Phone.qml")
    sidebar = source("shani/Modules/ControlCenter/SidebarDetails.qml")

    assert "function batteryText(dev)" in phone
    assert 'dev.charging ? " · " + Tr.t("charging")' in phone
    assert "dev.battery < 0" in phone
    # the row pulls the bridge device (which carries battery + charging) by id
    assert "Link.devices.find(d => d.id === devRow.modelData.id)" in sidebar
    assert "trailing: Phone.batteryText(devRow.linkDev)" in sidebar
    assert "Link.refresh();" in sidebar


def test_sunshine_pairing_stays_in_the_shell():
    """Fix 3: no browser hand-off; the PIN is read in-shell with a Copy fallback."""
    sharing = source("shani/Modules/Settings/SettingsSharing.qml")

    assert "xdg-open" not in sharing
    assert "id: pinProc" in sharing
    assert "curl -sk --max-time 6" in sharing
    assert 'Tr.t("Pairing PIN: %1").arg(page.pairPin)' in sharing
    assert 'Tr.t("Copy PIN")' in sharing
    assert 'Tr.t("Copy pairing address")' in sharing
    assert (
        'Quickshell.clipboardText = page.pairPin !== "" ? page.pairPin : page.pairUrl'
        in sharing
    )
    assert "self-signed certificate" in sharing


def test_cast_is_stateful_with_a_stop_button():
    """Fix 4: the launcher process is owned by Cast, so active/stop are real."""
    cast = source("shani/Services/Cast.qml")
    sharing = source("shani/Modules/Settings/SettingsSharing.qml")

    assert "readonly property bool active: session.running" in cast
    assert "function open() { if (!session.running) session.running = true; }" in cast
    assert "function stop() { if (session.running) session.running = false; }" in cast
    assert "id: session" in cast and "running: false" in cast
    assert "Cast.active" in sharing
    assert 'Tr.t("Stop casting")' in sharing
    assert "Cast.stop()" in sharing
