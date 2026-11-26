"""Doshas, worked from the classical rules.

Mangal dosha: Mars in houses 1, 2, 4, 7, 8 or 12 from the ascendant, the
Moon or Venus, cancelled by Mars' own/exalted sign, Jupiter's or Venus'
aspect (5th/7th/9th or conjunction), or Mars with the Sun in Leo. Kaal Sarp
dosha and Sade Sati are covered further down this file.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import astronomy as a  # noqa: E402


def chart(asc=0.0, **longitudes):
    planets = [
        {"name": name, "sidereal_longitude": value}
        for name, value in longitudes.items()
    ]
    return {"ascendant": asc, "planets": planets}


def test_mars_in_the_second_from_the_ascendant_has_dosha():
    """Aries rising, Mars at 40° (Taurus): house ((40-0)//30)+1 = 2.
    Mars is not in its own/exalted sign and no planet aspects it, so the
    dosha is present and effective.
    """
    r = a.mangal_dosha(chart(0.0, Mars=40.0))
    assert r["present"] is True and r["effective"] is True
    assert r["houses"]["ascendant"] == {"origin": 0.0, "house": 2, "afflicted": True}
    assert r["mars_house_from_ascendant"] == 2
    assert r["mars_sign"] == "Taurus"


def test_mars_in_the_third_from_the_ascendant_has_no_dosha():
    """Aries rising, Mars at 70° (Gemini): house 3, not one of the six."""
    r = a.mangal_dosha(chart(0.0, Mars=70.0))
    assert r["present"] is False and r["effective"] is False
    assert set(r["houses"]) == {"ascendant"}


def test_mars_in_the_seventh_from_the_ascendant_has_dosha():
    """Aries rising, Mars at 190° (Libra): house ((190)//30)+1 = 7."""
    r = a.mangal_dosha(chart(0.0, Mars=190.0))
    assert r["houses"]["ascendant"]["house"] == 7
    assert r["effective"] is True


def test_mars_in_its_own_sign_cancels_the_dosha():
    """Aries rising, Mars at 10° (Aries): house 1 is afflicted, but Mars is
    in its own sign, which cancels the dosha."""
    r = a.mangal_dosha(chart(0.0, Mars=10.0))
    assert r["present"] is True
    assert r["cancellations"] == ["mars_own_or_exalted"]
    assert r["effective"] is False


def test_jupiter_aspect_cancels_the_dosha():
    """Mars at 40° (Taurus), Jupiter at 150° (Virgo): (1-5)%12 = 8, the
    9th aspect from Jupiter; the dosha is present but cancelled."""
    r = a.mangal_dosha(chart(0.0, Mars=40.0, Jupiter=150.0))
    assert r["present"] is True
    assert r["cancellations"] == ["jupiter_aspect_or_conjunct"]
    assert r["effective"] is False


def test_houses_from_the_moon_and_venus_are_checked_too():
    """Mars at 40° (Taurus). Moon at 350° (Pisces): (40-350)%360 = 50,
    house 2 (afflicted). Venus at 280° (Capricorn): (40-280)%360 = 120,
    house 5 (not afflicted). Venus at 280° does aspect Mars? (1-9)%12=4,
    the 5th aspect from Venus, so it cancels the dosha."""
    r = a.mangal_dosha(chart(0.0, Mars=40.0, Moon=350.0, Venus=280.0))
    assert r["houses"]["moon"]["house"] == 2
    assert r["houses"]["venus"]["house"] == 5
    assert r["houses"]["moon"]["afflicted"] is True
    assert r["houses"]["venus"]["afflicted"] is False
    assert "venus_aspect_or_conjunct" in r["cancellations"]
    assert r["effective"] is False


def test_both_partners_with_mangal_cancel_it_for_matching():
    """Two charts each with Mars in the 2nd from the ascendant: both have
    effective dosha, so the matching cancellation applies."""
    first = chart(0.0, Mars=40.0)
    second = chart(90.0, Mars=130.0)
    pair = a.mangal_match(first, second)
    assert pair["partner_a"]["effective"] is True
    assert pair["partner_b"]["effective"] is True
    assert pair["both"] is True and pair["cancelled"] is True
    assert pair["dosha_for_matching"] is False
    lone = a.mangal_match(first, chart(0.0, Mars=70.0))
    assert lone["both"] is False and lone["dosha_for_matching"] is True


def test_guna_milan_carries_the_mangal_matching_result():
    moon_only = lambda value: {
        "planets": [{"name": "Moon", "sidereal_longitude": value}]
    }
    r = a.ashtakoota_guna_milan(moon_only(0.0), moon_only(0.0))
    assert r["mangal_dosha"]["both"] is False
    assert r["mangal_dosha"]["dosha_for_matching"] is False


def test_a_chart_without_mars_is_not_a_crash_in_matching():
    with pytest.raises(ValueError):
        a.mangal_dosha({"planets": []})


def hemmed_chart(rahu_longitude):
    """Seven planets placed 10-175 degrees after Rahu, well inside the
    Rahu-to-Ketu half of the zodiac."""
    values = {
        "Sun": 10,
        "Moon": 40,
        "Mercury": 70,
        "Venus": 100,
        "Mars": 130,
        "Jupiter": 160,
        "Saturn": 175,
        "Rahu": 0,
    }
    return chart(
        0.0,
        **{name: (value + rahu_longitude) % 360 for name, value in values.items()},
    )


def test_kaal_sarp_when_all_seven_planets_are_between_the_nodes():
    """Rahu at 10° Aries (house 1 from Aries rising) and Ketu at 10° Libra.
    All seven planets lie between 10° and 190°, so the dosha is present and
    the named yoga for Rahu in house 1 is Anapha.
    """
    r = a.kaal_sarpa_dosha(hemmed_chart(10.0))
    assert r["present"] is True
    assert r["type"] == "Anapha"
    assert r["rahu_house"] == 1 and r["ketu_house"] == 7
    assert len(r["planets_between"]) == 7
    assert r["planets_outside"] == []


def test_kaal_sarp_absent_when_one_planet_is_beyond_ketu():
    """Rahu at 10°, Ketu at 190°: Saturn at 185°+10° = 195° is past Ketu."""
    c = hemmed_chart(10.0)
    saturn = next(p for p in c["planets"] if p["name"] == "Saturn")
    saturn["sidereal_longitude"] = 195.0
    r = a.kaal_sarpa_dosha(c)
    assert r["present"] is False
    assert "Saturn" in r["planets_outside"]


def test_kaal_sarp_type_follows_rahus_house():
    """Rahu at 45° (Taurus) is house 2 from Aries rising: Durdhara."""
    r = a.kaal_sarpa_dosha(hemmed_chart(45.0))
    assert r["rahu_house"] == 2 and r["ketu_house"] == 8
    assert r["type"] == "Durdhara"


def test_sade_phase_from_the_moon_sign_by_hand():
    """Pisces is the 12th from Aries, Taurus the 2nd, Cancer the 4th."""
    assert a.sade_phase(0, 330.0) == "12th"  # Pisces
    assert a.sade_phase(0, 10.0) == "1st"  # Aries
    assert a.sade_phase(0, 40.0) == "2nd"  # Taurus
    assert a.sade_phase(0, 100.0) is None  # Cancer


def test_sade_sati_dates_bracket_the_moment_and_keep_phase_order():
    """Saturn's sidereal sign against an Aries Moon decides the phase.
    Stepping finds a start before the moment and an end after it when the
    phase is running; otherwise the next phase starts later.
    """
    when = "2026-11-26T00:00:00Z"
    jd = a.julian_day(when)
    expected = a.sade_phase(0, a._saturn_sidereal(jd))
    r = a.sade_sati(chart(0.0, Moon=0.0), now=when)
    assert r["phase"] == expected
    assert r["running"] == (expected is not None)
    assert r["method"] == "stepping_saturn"
    assert r["phases"][0]["phase"] == expected
    if expected is not None:
        assert a.julian_day(r["start"]) <= jd < a.julian_day(r["end"])
    else:
        assert a.julian_day(r["start"]) > jd
    if expected is not None:
        assert [p["phase"] for p in r["phases"]] == ["12th", "1st", "2nd"][
            ["12th", "1st", "2nd"].index(expected) :
        ]
