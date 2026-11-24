"""Static regressions for the pass-16 tray/status-icon fixes.

QML cannot run under pytest, but these bindings are the bits that silently rot:
a hide-glyph setting that never gates the glyph, a connectivity state the
network icon ignores, a hotspot that has no persistent bar cue, and an updates
dot that cannot be clicked.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_hide_volume_glyph_hides_the_speaker():
    """The speaker Icon must be gated on !hideVolumeGlyph; hideBrightnessGlyph
    is left alone (there is no brightness glyph in the bar)."""
    bar = source("shani/Modules/Bar/Bar.qml")
    speaker = bar[
        bar.index("name: Audio.icon") - 80 : bar.index("name: Audio.icon") + 300
    ]
    assert "visible: !Settings.data.hideVolumeGlyph" in speaker
    assert "hideBrightnessGlyph" not in speaker


def test_connected_without_internet_is_not_painted_as_working_wifi():
    """Net.icon/label must recognise connected && !online && !portal, returning
    an offline icon and a 'No internet' label instead of full signal bars."""
    net = source("shani/Services/Net.qml")
    assert "if (!online && !portal)" in net
    assert 'return "network-wireless-offline"' in net
    assert 'activeWifi && !online ? Tr.t("No internet")' in net


def test_hotspot_has_a_persistent_bar_indicator():
    """The status cluster needs a hotspot Icon bound to Net.hotspotOn with an
    accessible name, so a broadcasting machine has a cue after the panel closes."""
    bar = source("shani/Modules/Bar/Bar.qml")
    cluster = bar[
        bar.index("Icon { visible: Net.vpnActive") : bar.index(
            "Icon { visible: Net.vpnActive"
        )
        + 700
    ]
    assert "visible: Net.hotspotOn" in cluster
    assert '"network-wireless-hotspot"' in cluster
    assert "Accessible.name: Tr.t(" in cluster


def test_updates_dot_has_a_click_path_to_updates_open():
    """The amber dot on the clock needs its own MouseArea so a tap opens
    Updates rather than just toggling the generic control centre."""
    bar = source("shani/Modules/Bar/Bar.qml")
    dot = bar[
        bar.index("// an update waiting: a dot on the clock") : bar.index(
            "// an update waiting: a dot on the clock"
        )
        + 900
    ]
    assert "visible: Updates.attention" in dot
    assert "onClicked: Updates.open()" in dot
