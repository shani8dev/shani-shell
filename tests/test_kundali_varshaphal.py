"""Varshaphal: the solar return and the Tajika year chart.

The Sun returns to the natal sidereal longitude once a tropical year; for
a 1 January birth that is around 1 January of the requested year. Muntha
moves one whole sign (30°) for each completed year from the natal ascendant,
and the year lord is the natural lord of the return chart's Sun sign.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import astronomy as a  # noqa: E402

BIRTH = "1990-01-01T06:30:00Z"
PLACE = (18.5204, 73.8567)


@pytest.fixture
def natal():
    return a.compute_chart(BIRTH, *PLACE)


def test_solar_return_brings_the_sun_back_to_its_natal_longitude(natal):
    sun = next(p for p in natal["planets"] if p["name"] == "Sun")
    natal_longitude = sun["sidereal_longitude"]
    for year in (2025, 2026, 2027):
        instant = a.solar_return_instant(natal_longitude, year)
        assert instant.startswith(f"{year}-01-0")
        jd = a.julian_day(instant)
        returned = a._sun_sidereal(jd)
        assert abs((returned - natal_longitude + 180) % 360 - 180) < 0.01


def test_varshaphal_data_and_year_lord(natal):
    result = a.varshaphal(natal, 2026)
    assert result["system"] == "varshaphal" and result["year"] == 2026
    assert result["birth_place"] == {"latitude": PLACE[0], "longitude": PLACE[1]}
    assert result["solar_return"].startswith("2026-01-")
    assert len(result["planets"]) == 12
    return_sun = next(p for p in result["planets"] if p["name"] == "Sun")
    sign_index = a.SIGNS.index(return_sun["sign"])
    assert result["year_lord"] == a.SIGN_LORDS[sign_index]
    assert result["year_lord_sign"] == return_sun["sign"]


def test_muntha_advances_one_sign_per_year(natal):
    """Muntha = natal ascendant + (year - birth year) * 30 degrees.
    Birth year 1990, ascendant 338.8459: for 2026 that is 338.8459 + 36*30
    = 338.8459 (mod 360), i.e. Pisces; for 2027 it is Aries.
    """
    first = a.varshaphal(natal, 2026)["muntha"]
    second = a.varshaphal(natal, 2027)["muntha"]
    assert first["sign"] == "Pisces" and first["lord"] == "Jupiter"
    assert second["sign"] == "Aries" and second["lord"] == "Mars"
    assert (second["longitude"] - first["longitude"]) % 360 == pytest.approx(30.0)


def test_return_chart_is_cast_at_the_birth_place(natal):
    result = a.varshaphal(natal, 2026)
    at_place = a.compute_chart(result["solar_return"], *PLACE)
    assert result["ascendant"] == pytest.approx(at_place["ascendant"])
    for ours, theirs in zip(result["planets"], at_place["planets"]):
        assert ours["longitude"] == theirs["sidereal_longitude"]


def test_a_chart_without_a_sun_is_an_error():
    with pytest.raises(ValueError):
        a.varshaphal({"planets": []}, 2026)
