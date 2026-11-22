"""Static checks for the tray/status-icon fixes (16th pass).

Each fix is asserted against the QML source, so a regression that silently
removes the binding is caught without a running shell.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text(encoding="utf-8")


def icon_block(text, name_token):
    """Body of the Icon{...} whose `name:` binding contains name_token."""
    for m in re.finditer(r"\bIcon\s*\{", text):
        i = m.end() - 1
        depth = 0
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    body = text[i + 1 : j]
                    if re.search(r"\bname\s*:\s*[^;]*" + re.escape(name_token), body):
                        return body
                    break
    return ""


def test_wifi_tile_uses_the_computed_network_icon():
    s = read("shani/Modules/ControlCenter/SidebarTiles.qml")
    assert "icon: Net.icon" in s
    assert "network-wireless-signal-excellent" not in s


def test_bar_vpn_icon_covers_tailscale():
    s = read("shani/Modules/Bar/Bar.qml")
    assert "visible: Net.vpnActive || Net.tailscaleUp" in s


def test_status_icons_have_live_accessible_names():
    s = read("shani/Modules/Bar/Bar.qml")
    for token in ("Audio.icon", "Power.batteryIcon", "Net.icon"):
        body = icon_block(s, token)
        assert body, f"no Icon found for {token}"
        m = re.search(r"Accessible\.name\s*:\s*([^\n]+)", body)
        assert m, f"{token} icon has no Accessible.name"
        assert any(k in m.group(1) for k in ("Audio.", "Power.", "Net.", "Tr.t(")), (
            token,
            m.group(1),
        )


def test_focus_icon_depends_only_on_focus():
    s = read("shani/Modules/Bar/Bar.qml")
    body = icon_block(s, "Focus.mode")
    assert body
    assert "visible: Focus.on" in body
    assert "hideVolumeGlyph" not in body
    assert "hideBrightnessGlyph" not in body
