"""Static checks for Bar round-2 fixes (AT names, keyboard scroll, tray/rename state)."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_tray_button_exposes_accessible_button():
    text = read("shani/Modules/Bar/Bar.qml")
    # TrayButton component must be an AT button, not just a KeyFocus target.
    m = re.search(r"component TrayButton: Item \{(.*?)\n        \}", text, re.DOTALL)
    assert m, "TrayButton component missing"
    block = m.group(1)
    assert "Accessible.role: Accessible.Button" in block
    assert "Accessible.name:" in block
    assert "Accessible.onPressAction:" in block


def test_status_cluster_icons_have_accessible_names():
    text = read("shani/Modules/Bar/Bar.qml")
    # Icons inside the quick-settings cluster that convey state must be named.
    for needle in [
        'Focus.on; name: Focus.mode ? Focus.mode.icon : ""',
        "Idle.caffeine || Idle.keptAwake; name: \"preferences-desktop-screensaver\"",
        "Net.vpnActive || Net.tailscaleUp; name: \"network-vpn\"",
        "Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled",
        "Audio.micMuted && Audio.source !== null; name: \"microphone-sensitivity-muted\"",
    ]:
        idx = text.index(needle)
        # Accessible.name should appear within the same Icon block (next ~200 chars).
        window = text[idx:idx + 500]
        assert "Accessible.name:" in window, f"missing Accessible.name near: {needle[:60]}"


def test_tray_drawer_closes_when_bar_hidden():
    text = read("shani/Modules/Bar/Bar.qml")
    # Hidden bar must not leave the overflow popup dangling.
    assert re.search(
        r"onShownChanged:\s*\{[^}]*if\s*\(!shown\)\s*bar\.trayOpen\s*=\s*false",
        text,
    )


def test_workspace_rename_input_has_accessible_name():
    text = read("shani/Modules/Bar/Bar.qml")
    # The inline rename field is keyboard-reachable; give it an AT name.
    m = re.search(r"TextInput \{(?P<b>.*?)onVisibleChanged:", text, re.DOTALL)
    assert m, "workspace rename TextInput missing"
    block = m.group("b")
    assert "Accessible.role: Accessible.EditableText" in block
    assert "Accessible.name:" in block


def test_chip_supports_keyboard_scroll():
    chip = read("shani/Modules/Bar/Chip.qml")
    assert re.search(r"property bool scrollable:\s*false", chip)
    kf = re.search(r"KeyFocus \{([^}]*)\}", chip, re.DOTALL)
    assert kf, "Chip KeyFocus missing"
    block = kf.group(1)
    assert "slider:" in block
    assert "onStep:" in block
    bar = read("shani/Modules/Bar/Bar.qml")
    # The volume chip must opt in.
    assert re.search(r"onScrolled: d => Audio\.step\(d \* 0\.05\)", bar)
    assert "scrollable: true" in bar
