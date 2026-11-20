"""bridge/powerlimit.py and shani-admin.py's `power-limit`: a handheld's chip
power limit, the two ways the kernel offers it (as Ananta OS's gamingd):
ASUS firmware attributes (watts; pl2/fppt follow pl1) and the AMD graphics
driver's hwmon power1_cap (microwatts). A non-AMD card is not used."""
import importlib.util
import json
from pathlib import Path

import pytest

BRIDGE = Path(__file__).resolve().parent.parent / "bridge"


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, BRIDGE / file)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def write(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f"{v}\n")


@pytest.fixture
def asus(tmp_path):
    a = tmp_path / "sys/class/firmware-attributes/asus-armoury/attributes"
    for attr in ("ppt_pl1_spl", "ppt_pl2_sppt", "ppt_fppt"):
        write(a / attr / "current_value", 17); write(a / attr / "min_value", 7); write(a / attr / "max_value", 30)
    return tmp_path / "sys", a


@pytest.fixture
def amd(tmp_path):
    s = tmp_path / "sys"
    write(s / "class/drm/card0/device/vendor", "0x8086")            # an Intel card first: not used
    hw = s / "class/drm/card1/device/hwmon/hwmon4"
    write(s / "class/drm/card1/device/vendor", "0x1002")
    write(hw / "power1_cap", 15_000_000); write(hw / "power1_cap_min", 0); write(hw / "power1_cap_max", 30_000_000)
    return s, hw


def test_show_asus(asus, monkeypatch, capsys):
    s, _ = asus
    monkeypatch.setenv("SHANI_SYSFS", str(s))
    assert load("pl", "powerlimit.py").main(["x", "show"]) == 0
    assert json.loads(capsys.readouterr().out) == {"method": "asus", "min": 7, "max": 30, "current": 17}


def test_show_amdgpu_floors_at_3_watts(amd, monkeypatch, capsys):
    s, _ = amd
    monkeypatch.setenv("SHANI_SYSFS", str(s))
    load("pl2", "powerlimit.py").main(["x", "show"])
    assert json.loads(capsys.readouterr().out) == {"method": "amdgpu", "min": 3, "max": 30, "current": 15}


def test_show_none(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("SHANI_SYSFS", str(tmp_path))
    load("pl3", "powerlimit.py").main(["x", "show"])
    assert capsys.readouterr().out.strip() == "null"


def admin(monkeypatch, s, tmp_path):
    sa = load("sa_pl", "shani-admin.py")
    monkeypatch.setattr(sa, "SYSFS", s)
    monkeypatch.setattr(sa, "POWER_LIMIT_TMPFILES", tmp_path / "pl.conf")
    return sa


def test_set_asus_moves_all_three(asus, tmp_path, monkeypatch):
    s, a = asus
    sa = admin(monkeypatch, s, tmp_path)
    assert sa.power_limit({"watts": 25}) == {"watts": 25}
    for attr in ("ppt_pl1_spl", "ppt_pl2_sppt", "ppt_fppt"):
        assert (a / attr / "current_value").read_text() == "25\n"
    assert f"w {a}/ppt_pl1_spl/current_value - - - - 25" in (tmp_path / "pl.conf").read_text()


def test_set_amdgpu_in_microwatts(amd, tmp_path, monkeypatch):
    s, hw = amd
    sa = admin(monkeypatch, s, tmp_path)
    sa.power_limit({"watts": 12})
    assert (hw / "power1_cap").read_text() == "12000000\n"


@pytest.mark.parametrize("req,why", [({"watts": 40}, "between 7 and 30"), ({"watts": 5}, "between 7 and 30"),
                                     ({"watts": "25"}, "whole number"), ({"watts": True}, "whole number")])
def test_refused(asus, tmp_path, monkeypatch, req, why):
    s, a = asus
    sa = admin(monkeypatch, s, tmp_path)
    with pytest.raises(sa.Refused, match=why):
        sa.power_limit(req)
    assert (a / "ppt_pl1_spl/current_value").read_text() == "17\n"


def test_no_limit_here(tmp_path, monkeypatch):
    sa = admin(monkeypatch, tmp_path, tmp_path)
    with pytest.raises(sa.Refused, match="cannot be changed"):
        sa.power_limit({"watts": 10})
