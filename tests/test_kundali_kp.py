"""KP lords and real Placidus/Koch cusps.

Placidus divides the semi-arc of a point (cos SA = -tan(latitude) tan(dec))
into thirds in right ascension. At the equator every semi-arc is 90°, so
cusp 11 is at RA 30°, cusp 12 at RA 60°, cusp 2 at RA 120° and cusp 3 at
RA 150° from the RAMC. Koch's cusps use the MC semi-arc measured back and
forth from birth and coincide with Placidus on the equator.

The sub and sub-sub lords divide the nakshatra in Vimshottari proportions
(Ketu 7, Venus 20, Sun 6, Moon 10, Mars 7, Rahu 18, Jupiter 16, Saturn 19,
Mercury 17, out of 120); the sub-sub periods start with the sub lord.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import astronomy as a  # noqa: E402

EPS = 23.4393


def ra(lon):
    return a._ra_of_lon(lon, EPS)


def test_placidus_at_the_equator_trisects_the_semiarc_in_ra():
    """MC at longitude 0 (RAMC 0) on the equator: SA = 90 for every
    longitude, so the intermediate RA offsets are 30, 60, 120 and 150.
    """
    asc = a._asc_from_ramc(0.0, 0.0, EPS)
    cusps = a._placidus_cusps(asc, 0.0, 0.0, EPS)
    assert ra(cusps[10]) == pytest.approx(30.0, abs=1e-6)  # house 11
    assert ra(cusps[11]) == pytest.approx(60.0, abs=1e-6)  # house 12
    assert ra(cusps[1]) == pytest.approx(120.0, abs=1e-6)  # house 2
    assert ra(cusps[2]) == pytest.approx(150.0, abs=1e-6)  # house 3
    assert cusps[9] == pytest.approx(0.0, abs=1e-6)  # MC
    assert cusps[0] == pytest.approx(asc, abs=1e-6)  # ascendant


def test_opposite_cusps_are_one_hundred_eighty_degrees_apart():
    """Every house cusp has its opposite six houses later."""
    asc, mc, lat = 75.0, 10.0, 28.6
    cusps = a._placidus_cusps(asc, mc, lat, EPS)
    for i in range(6):
        assert (cusps[i + 6] - cusps[i]) % 360 == pytest.approx(180.0, abs=1e-6)


def test_polar_latitudes_fall_back_to_equal_houses():
    """Placidus is undefined above 66.56°, where the fallback is equal."""
    cusps = a._placidus_cusps(20.0, 300.0, 70.0, EPS)
    assert [round(x, 6) for x in cusps] == [round(20.0 + 30 * i, 6) for i in range(12)]


def test_koch_agrees_with_placidus_at_the_equator_but_not_at_latitude():
    """Both use the MC semi-arc; Koch measures it from the birth moment."""
    asc = a._asc_from_ramc(0.0, 0.0, EPS)
    p = a._placidus_cusps(asc, 0.0, 0.0, EPS)
    k = a._koch_cusps(asc, 0.0, 0.0, EPS)
    assert p == pytest.approx(k, abs=1e-4)
    p = a._placidus_cusps(75.0, 10.0, 28.6, EPS)
    k = a._koch_cusps(75.0, 10.0, 28.6, EPS)
    assert p != pytest.approx(k, abs=1e-2)


def test_sub_lord_divides_the_nakshatra_by_vimshottari_years():
    """Ashwini (0-13.333°) is ruled by Ketu, whose sub is 7/120 of the star,
    i.e. 0-0.7778°. At 0.02° the sub and sub-sub are Ketu (the sub-sub's
    Ketu share is another 7/120, i.e. 0.045°); at 1° the sub is Venus.
    """
    assert a.kp_sub_lord(0.02) == "Ketu"
    assert a.kp_sub_lord(0.02, 2) == "Ketu"
    assert a.kp_sub_lord(1.0) == "Venus"


def test_sub_sub_lord_starts_the_sequence_with_the_sub_lord():
    """At 0.5° the sub is Ketu, 0.6429 through Ketu's own sub period.
    Within that: Ketu 7 + Venus 20 + Sun 6 + Moon 10 + Mars 7 + Rahu 18
    = 68 of 120 before Jupiter's 16/120, so the sub-sub lord is Jupiter.
    """
    assert a.kp_sub_lord(0.5) == "Ketu"
    assert a.kp_sub_lord(0.5, 2) == "Jupiter"


def test_star_lord_changes_at_the_next_nakshatra():
    """Bharani begins at 13.333° and is ruled by Venus. At 10° the
    fraction through Ashwini is 10/13.333 = 0.75, inside Saturn's sub
    period (Jupiter ends at 0.70, Saturn at 0.8583).
    """
    assert a.kp_sub_lord(10.0) == "Saturn"
    assert a.kp_sub_lord(13.4) == "Venus"
    assert a.kp_sub_lord(13.4, 2) == "Venus"


def test_kp_lords_from_a_real_chart_cover_planets_and_cusps():
    chart = a.compute_chart("1990-01-01T06:30:00Z", 18.5204, 73.8567)
    data = a.kp_lords(chart)
    assert data["system"] == "KP" and data["house_system"] == "Placidus"
    assert len(data["points"]) == len(chart["planets"]) == 12
    assert len(data["cusps"]) == 12
    required = {
        "name",
        "longitude",
        "sign",
        "sign_lord",
        "star_lord",
        "sub_lord",
        "sub_sub_lord",
    }
    for point in data["points"] + data["cusps"]:
        assert required <= set(point)
        assert point["sub_lord"] in a.DASHA_LORDS
        assert point["sub_sub_lord"] in a.DASHA_LORDS
        assert point["sign_lord"] == a.SIGN_LORDS[a.SIGNS.index(point["sign"])]
    assert data["cusps"][0]["longitude"] == pytest.approx(
        round(chart["ascendant"], 4), abs=1e-3
    )
