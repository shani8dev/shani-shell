"""Ashtakoota guna milan, worked by hand from the classical tables.

All positions below are sidereal Moon longitudes. The tables used are the
standard Ashtakoota ones: varna by Moon sign (Brahmin > Kshatriya > Vaishya
> Shudra), vashya by sign with Sagittarius/Capricorn split at 15°, tara by an
inclusive count of nakshatras from one Moon to the other, yoni by the 14
animals, graha maitri by the natural friendship of the two sign lords (Sun,
Moon, Mars, Mercury, Jupiter, Venus, Saturn order), gana and nadi by
nakshatra, bhakoot by the 2-12, 5-9 and 6-8 sign distances. Every expected
total in this file is added up by hand in the test's docstring.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bridge"))
import astronomy as a  # noqa: E402


def chart(moon_longitude: float) -> dict:
    return {"planets": [{"name": "Moon", "sidereal_longitude": moon_longitude}]}


def scores(result):
    return {k["name"]: k["score"] for k in result["kootas"]}


def test_an_identical_chart_scores_thirty_three_and_keeps_janma_tara():
    """Same Ashwini Moon (0°):
    varna 1 (same), vashya 2 (same Chatushpada), tara 0 (Janma both ways),
    yoni 4 (same Horse), graha maitri 5 (same lord Mars), gana 6 (same Deva),
    bhakoot 7 (distance 1), nadi 8 (same nakshatra cancels nadi dosha).
    1+2+0+4+5+6+7+8 = 33 -> excellent (33-36).
    """
    r = a.ashtakoota_guna_milan(chart(0.0), chart(0.0))
    assert scores(r) == {
        "varna": 1,
        "vashya": 2,
        "tara": 0,
        "yoni": 4,
        "graha_maitri": 5,
        "gana": 6,
        "bhakoot": 7,
        "nadi": 8,
    }
    assert r["total"] == 33 and r["band"] == "33_36" and r["verdict"] == "excellent"
    assert r["kootas"][2]["groom_tara"] == "Janma"
    assert r["nadi_dosha"]["cancellation"] == "same_nakshatra"
    assert r["nadi_dosha"]["present"] is False


def test_rohini_groom_ashwini_bride_is_worked_from_the_tables():
    """Groom Moon Rohini 40° (Taurus), bride Ashwini 0° (Aries):
    varna 0 (Vaishya is below Kshatriya), vashya 2 (both Chatushpada),
    tara 2 (Kshema one way, Naidhana the other), yoni 2 (Serpent/Horse, gap 3),
    graha maitri 4 (Venus/Mars friend-neutral), gana 5 (Manushya/Deva),
    bhakoot 7 (distance 12 but the lords are friends -> cancelled), nadi 8.
    0+2+2+2+4+5+7+8 = 30 -> good (25-32).
    """
    r = a.ashtakoota_guna_milan(chart(40.0), chart(0.0))
    assert scores(r) == {
        "varna": 0,
        "vashya": 2,
        "tara": 2,
        "yoni": 2,
        "graha_maitri": 4,
        "gana": 5,
        "bhakoot": 7,
        "nadi": 8,
    }
    assert r["total"] == 30 and r["band"] == "25_32"
    assert r["bhakoot_dosha"]["present"] is True
    assert r["bhakoot_dosha"]["cancelled"] is True
    assert r["partner_a"]["nakshatra"] == "Rohini"
    assert r["partner_b"]["nakshatra"] == "Ashwini"


def test_same_nadi_gives_nadi_dosha_and_zero_points():
    """Ashwini 0° (Aries, Adi nadi) vs Ardra 70° (Gemini, Adi nadi):
    varna 1, vashya 1 (Chatushpada/Manav), tara 2 (Pratyak/Sadhaka),
    yoni 2 (Horse/Dog, gap 4), graha maitri 1 (Mars/Mercury enemies),
    gana 5 (Deva/Manushya), bhakoot 7 (distance 11), nadi 0 (same nadi).
    1+1+2+2+1+5+7+0 = 19 -> average (18-24).
    """
    r = a.ashtakoota_guna_milan(chart(0.0), chart(70.0))
    assert scores(r)["nadi"] == 0
    assert r["total"] == 19 and r["band"] == "18_24"
    assert r["nadi_dosha"]["present"] is True
    assert r["nadi_dosha"]["cancellation"] is None


def test_nadi_dosha_exception_same_sign_different_nakshatra():
    """Both Moons in Taurus: Krittika 31° and Rohini 40° are both Antya
    nadi. A different nakshatra in the same sign cancels the dosha.
    """
    r = a.ashtakoota_guna_milan(chart(31.0), chart(40.0))
    assert r["nadi_dosha"]["present"] is False
    assert r["nadi_dosha"]["cancellation"] == "same_sign_different_nakshatra"
    assert scores(r)["nadi"] == 8


def test_vashya_split_at_fifteen_degrees():
    """Sagittarius 10° is Manav; Sagittarius 20° is Chatushpada."""
    assert a._vashya(240 + 10) == "Manav"
    assert a._vashya(240 + 20) == "Chatushpada"
    assert a._vashya(270 + 10) == "Chatushpada"
    assert a._vashya(270 + 20) == "Jalchar"


def test_enemy_yonis_score_zero():
    """Ashwini is Horse, Hasta (165°) is Buffalo: enemy yonis -> 0."""
    r = a.ashtakoota_guna_milan(chart(0.0), chart(165.0))
    assert scores(r)["yoni"] == 0
    assert (
        next(k for k in r["kootas"] if k["name"] == "yoni")["reason"] == "enemy_yonis"
    )


def test_bhakoot_dosha_without_a_cancellation():
    """Groom Moon Virgo 150° (Mercury), bride Moon Aries 0° (Mars):
    distance = ((8-0)%12)+1 = 9, one of the inauspicious 5-9 distances.
    Mercury and Mars are natural enemies (Graha Maitri 1), so neither
    cancellation (same lord or friendly lords) applies: 0 points.
    """
    r = a.ashtakoota_guna_milan(chart(150.0), chart(0.0))
    assert scores(r)["bhakoot"] == 0
    assert r["bhakoot_dosha"]["present"] is True
    assert r["bhakoot_dosha"]["cancelled"] is False


def test_all_bands_are_reachable_and_the_data_is_plain():
    charts = [(0.0, 0.0), (40.0, 0.0), (0.0, 70.0), (150.0, 0.0)]
    seen = set()
    for g, b in charts:
        r = a.ashtakoota_guna_milan(chart(g), chart(b))
        assert isinstance(r["total"], (int, float))
        assert len(r["kootas"]) == 8
        assert all(
            set(("number", "name", "score", "max", "reason")) <= set(k)
            for k in r["kootas"]
        )
        expected = (
            "below_18"
            if r["total"] < 18
            else "18_24"
            if r["total"] <= 24
            else "25_32"
            if r["total"] <= 32
            else "33_36"
        )
        assert r["band"] == expected
        seen.add(r["band"])
    assert seen == {"below_18", "18_24", "25_32", "33_36"}


def test_a_chart_without_a_moon_is_an_error():
    with pytest.raises(ValueError):
        a.ashtakoota_guna_milan({"planets": []}, chart(0.0))


def test_the_bridge_returns_json_data_for_matching():
    import json
    import subprocess as sp

    tool = [sys.executable, str(ROOT / "bridge/kundali.py")]
    first = ["1990-01-01T12:00@Asia/Kolkata", "18.5204", "73.8567"]
    second = ["1991-02-02T13:00@Asia/Kolkata", "18.5204", "73.8567"]

    out = sp.run(
        tool + ["data", "ashtakoota", *first],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 0
    data = json.loads(out.stdout)
    assert data["total"] == 33 and len(data["kootas"]) == 8
    assert "text" not in data

    out = sp.run(
        tool + ["match", *first, *second], capture_output=True, text=True, timeout=60
    )
    assert out.returncode == 0
    pair = json.loads(out.stdout)
    assert set(("total", "verdict", "kootas", "nadi_dosha", "bhakoot_dosha")) <= set(
        pair
    )
    assert pair["total"] != data["total"]
    assert "Traceback" not in out.stderr
