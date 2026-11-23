"""Static regressions for the four remaining tray/status-icon fixes.

QML cannot run under pytest, so each fix is pinned against its source:
a binding that silently disappears is caught without a running shell.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_location_in_use_has_an_amber_bar_chip():
    loc = read("shani/Services/Location.qml")
    assert "property bool active: root.running" in loc
    bar = read("shani/Modules/Bar/Bar.qml")
    assert "visible: Location.active" in bar
    assert "tint: Theme.amber" in bar
    assert 'name: Tr.t("Location in use")' in bar
    assert 'Ui.openSettings("privacy")' in bar


def test_firewall_down_has_a_clickable_bar_chip():
    fw = read("shani/Services/Firewall.qml")
    assert "property bool probed: false" in fw
    bar = read("shani/Modules/Bar/Bar.qml")
    assert (
        "visible: Firewall.probed && (!Firewall.available || !Firewall.running)" in bar
    )
    assert "tint: Theme.red" in bar
    assert "hint: Tr.t(" in bar
    assert 'Ui.openSettings("firewall")' in bar


def test_disk_full_chip_has_a_lazy_bounded_df_poll():
    disk = read("shani/Services/DiskUsage.qml")
    assert '"df", "--output=pcent,target"' in disk
    assert "m.usedPct > 90" in disk
    assert 'Proc.run("diskusage-df"' in disk
    assert "}, 0, 10000);" in disk  # no debounce, 10 s timeout
    assert "interval: 60000" in disk
    assert "running: Settings.loaded" in disk
    bar = read("shani/Modules/Bar/Bar.qml")
    assert "visible: DiskUsage.anyFull" in bar
    assert "onClicked: DiskUsage.open()" in bar


def test_peripheral_low_battery_normalises_the_boundary():
    bar = read("shani/Modules/Bar/Bar.qml")
    assert "function peripheralPct(d)" in bar
    assert "p < 1 ? p * 100 : p" in bar  # 1 is 1 %, not 100 %
    assert "bar.peripheralPct(first)" in bar
    assert "d.percentage <= 1 ?" not in bar
