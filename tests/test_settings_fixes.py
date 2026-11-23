"""Static checks for the pass-21/22 settings fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_reduce_transparency_stops_compositor_blur():
    s = read("shani/Common/Settings.qml")
    line = next(l for l in s.splitlines() if "property bool blurWanted" in l)
    assert "data.blur" in line
    assert "!data.reduceTransparency" in line
    assert "!data.highContrast" in line


def test_update_channel_toggle_uses_latest():
    a = read("shani/Modules/Settings/SettingsAbout.qml")
    assert 'Updates.channel === "latest" ? Tr.t("Latest") : Tr.t("Stable")' in a
    assert 'Updates.setChannel(Updates.channel === "latest" ? "stable" : "latest")' in a
    assert '"beta"' not in a


def test_removing_leftover_is_declared_and_times_out():
    w = read("shani/Modules/Software/SoftwareWindow.qml")
    assert 'property string removingLeftover: ""' in w
    timer = next(l for l in w.splitlines() if "id: removeTimer" in l)
    assert 'win.removing = ""' in timer and 'win.removingLeftover = ""' in timer
    assert "win.removingLeftover = lrow.modelData.id; removeTimer.restart()" in w
