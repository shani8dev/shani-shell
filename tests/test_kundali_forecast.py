"""The days ahead for a saved birth (bridge/kundali_forecast.py).

Each rule is checked against the positions it is built on, computed here
independently, so a wrong offset (the 8th sign is +7, not +8; the tara counts
from the birth star inclusively) fails.
"""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import astronomy as a  # noqa: E402
import kundali_forecast as f  # noqa: E402

BIRTH = ("1990-01-01T12:00@Asia/Kolkata", 18.5204, 73.8567)   # Moon in Aquarius, Dhanishta


def _moon_sid(when: datetime) -> float:
    jd = a.julian_day(when.strftime("%Y-%m-%dT%H:%M:%SZ"))
    return (a._moon_longitude(jd) - a.ayanamsa_lahiri(jd)) % 360


def test_chandrashtama_is_the_moon_in_the_eighth_sign_from_the_birth_moon():
    out = f.forecast(*BIRTH, start=date(2026, 11, 26), days=30)
    flagged = [d["date"] for d in out["days"] if any(r["code"] == "chandrashtama" for r in d["reasons"])]
    assert flagged, "no chandrashtama in a month: the Moon passes every sign"
    virgo = a.SIGNS.index("Virgo")            # 8th from Aquarius
    for day in flagged:
        y, m, dd = map(int, day.split("-"))
        signs = {int(_moon_sid(datetime(y, m, dd, h, tzinfo=timezone.utc)) // 30) for h in (0, 6, 12, 18)}
        assert virgo in signs, day
    # and a day the Moon is nowhere near Virgo is not flagged
    for d in out["days"]:
        y, m, dd = map(int, d["date"].split("-"))
        signs = {int(_moon_sid(datetime(y, m, dd, h, tzinfo=timezone.utc)) // 30) for h in (0, 6, 12, 18)}
        if virgo not in signs:
            assert all(r["code"] != "chandrashtama" for r in d["reasons"]), d


def test_tara_counts_from_the_birth_star():
    out = f.forecast(*BIRTH, start=date(2026, 11, 26), days=9)
    birth = int(_moon_sid(datetime(1990, 1, 1, 6, 30, tzinfo=timezone.utc)) // (360 / 27))
    for d in out["days"]:
        y, m, dd = map(int, d["date"].split("-"))
        naks = [int(_moon_sid(datetime(y, m, dd, h, tzinfo=timezone.utc)) // (360 / 27)) for h in (0, 6, 12, 18)]
        assert d["tara"] in {f.TARAS[((n - birth) % 27) % 9] for n in naks}
        if d["tara"] in f.HARD_TARAS:
            assert d["tone"] in ("caution", "difficult")


def test_now_knows_the_running_periods_and_saturn():
    out = f.forecast(*BIRTH, start=date(2026, 11, 26), days=1)
    now = out["now"]
    assert now["moon_sign"] == "Aquarius"
    assert now["mahadasha"]["lord"] == "Saturn"
    # Saturn has been in Pisces since 2025: the 2nd from Aquarius, Sade Sati setting
    assert now["saturn_from_moon"] == 2 and now["saturn"] == "sade_sati_setting"


def test_a_period_that_begins_inside_the_days_is_listed():
    out = f.forecast(*BIRTH, start=date(2027, 2, 5), days=10)
    begun = [c for c in out["changes"] if c["kind"] == "antardasha"]
    assert begun and begun[0]["lord"] == "Mercury" and begun[0]["within"] == "Saturn", out["changes"]


def test_the_bridge_answers_json():
    r = subprocess.run([sys.executable, str(ROOT / "bridge/kundali_forecast.py"), BIRTH[0], str(BIRTH[1]),
                        str(BIRTH[2]), "2026-11-26", "7"], capture_output=True, text=True, timeout=60)
    data = json.loads(r.stdout)
    assert r.returncode == 0 and len(data["days"]) == 7 and "now" in data
    r = subprocess.run([sys.executable, str(ROOT / "bridge/kundali_forecast.py")], capture_output=True, text=True)
    assert r.returncode == 2 and "usage" in json.loads(r.stdout)["error"]


def test_sade_sati_is_in_now_and_a_phase_that_begins_is_a_change():
    out = f.forecast(*BIRTH, start=date(2026, 11, 26), days=3)
    ss = out["now"]["sade_sati"]
    assert ss["running"] and ss["phase"] == "setting" and ss["phases"][0]["end"].startswith("2027-06-0")
    # Saturn enters Aquarius (the 12th from a Pisces Moon) in 2023: for a Pisces
    # Moon the rising phase begins in that window - here, for this Aquarius Moon,
    # the next Sade Sati is decades away, so no phase begins in three days
    assert not [c for c in out["changes"] if c["kind"] == "sade_sati"]
    # a window over Saturn's 2025 move into Pisces: the setting phase begins
    out = f.forecast(*BIRTH, start=date(2025, 3, 25), days=10)
    assert [c for c in out["changes"] if c["kind"] == "sade_sati" and c["phase"] == "setting"], out["changes"]
