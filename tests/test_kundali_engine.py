"""The Kundali engine moved from shani-chronoa into shani-shell.

The engine is a plain module: no skill registration, no import of
``shani_chronoa`` at import time, and an injected astronomy module. These
tests pin that shape and the two commands the shell bridge routes through it.
"""

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))

import astronomy  # noqa: E402
import kundali  # noqa: E402
import kundali_engine  # noqa: E402


class FakeAstro:
    def compute_panchang(self, date_str, lat, lon):
        return {
            "tithi": "Shukla Pratipada",
            "vara": "Monday",
            "nakshatra": "Rohini",
            "yoga": "Vishkambha",
            "karana": "Bava",
            "sun_longitude": 280.1,
            "moon_longitude": 45.2,
            "ayanamsa": 24.0,
        }

    def compute_full_chart_v2(self, datetime_str, lat, lon):
        return {
            "ascendant": 95.5,
            "ascendant_sign": "Cancer",
            "ayanamsa": 24.0,
            "planets": [
                {
                    "name": "Moon",
                    "sign": "Taurus",
                    "degree": 15,
                    "minute": 30,
                    "sidereal_longitude": 45.5,
                    "retrograde": False,
                    "dignity": "own",
                },
            ],
            "houses": [
                {"house_number": 1, "sign": "Cancer", "degree": 5, "minute": 30},
            ],
        }

    def varga_longitude(self, longitude, divisional_chart):
        return 15.5

    SIGNS = [
        "Aries",
        "Taurus",
        "Gemini",
        "Cancer",
        "Leo",
        "Virgo",
        "Libra",
        "Scorpio",
        "Sagittarius",
        "Capricorn",
        "Aquarius",
        "Pisces",
    ]


@pytest.fixture
def fake_astro():
    return FakeAstro()


def test_astronomy_is_local_and_has_no_chronoa_shim():
    """The calculator now imports the astronomy module moved into bridge/."""
    assert (ROOT / "bridge" / "astronomy.py").is_file()
    assert kundali.astronomy is astronomy
    assert callable(astronomy.compute_panchang)
    assert callable(astronomy.compute_full_chart_v2)
    bridge = (ROOT / "bridge" / "kundali.py").read_text(encoding="utf-8")
    assert "shani_chronoa" not in bridge
    assert "/usr/lib/shani-chronoa" not in bridge
    assert "importlib" not in bridge


def test_engine_is_a_plain_module():
    """No skill registration or shani-chronoa import survives the move."""
    source = (ROOT / "bridge" / "kundali_engine.py").read_text(encoding="utf-8")
    assert "Skill(" not in source
    assert "SCHEMA" not in source
    assert "from shani_chronoa" not in source
    assert callable(kundali_engine.compute)


def test_panchang_is_rendered_from_the_injected_astronomy(fake_astro):
    text = kundali_engine.compute(
        {"action": "panchang", "date": "2024-01-01T12:00:00Z"}, fake_astro
    )
    for word in (
        "Panchang",
        "Tithi: Shukla Pratipada",
        "Vara: Monday",
        "Nakshatra: Rohini",
        "Yoga: Vishkambha",
        "Karana: Bava",
    ):
        assert word in text


def test_kundali_is_rendered_from_the_injected_astronomy(fake_astro):
    text = kundali_engine.compute(
        {"action": "kundali", "datetime": "1990-01-01T12:00:00Z"}, fake_astro
    )
    for word in (
        "Kundali (Sidereal, Lahiri)",
        "Ascendant: Cancer",
        "Moon: Taurus",
        "House 1: Cancer",
        "Navamsha (D9)",
    ):
        assert word in text


def test_unknown_action_is_reported_not_guessed(fake_astro):
    assert "Unknown action" in kundali_engine.compute(
        {"action": "nonesuch"}, fake_astro
    )


def test_bridge_panchang_keeps_the_fields_and_adds_the_engine_text(
    monkeypatch, fake_astro
):
    monkeypatch.setattr(kundali, "_astro", lambda: fake_astro)
    result = kundali.panchang("2024-01-01", 28.6, 77.2)
    assert result["tithi"] == "Shukla Pratipada"
    assert "Tithi" in result["text"]


def test_bridge_kundali_keeps_the_fields_and_adds_the_engine_text(
    monkeypatch, fake_astro
):
    monkeypatch.setattr(kundali, "_astro", lambda: fake_astro)
    result = kundali.kundali("1990-01-01", 28.6, 77.2)
    assert result["houses"] == [
        {"house_number": 1, "sign": "Cancer", "degree": 5, "minute": 30}
    ]
    assert "Ascendant" in result["text"]


class ChartAstro(FakeAstro):
    """A chart with the six sections the window draws."""

    def compute_full_chart_v2(self, datetime_str, lat, lon):
        chart = super().compute_full_chart_v2(datetime_str, lat, lon)
        chart["planets"][0]["sidereal_longitude"] = 45.5
        chart["dasha"] = {
            "mahadashas": [{"lord": "Moon", "years": 10, "start_offset": 0}]
        }
        chart["ashtakavarga"] = {"sarva": [3, 4]}
        chart["aspects"] = [
            {"planet1": "Moon", "aspect": "conjunct", "planet2": "Sun", "orb": 2}
        ]
        return chart

    def julian_day(self, when):
        return 2460000.5

    def _sun_longitude(self, jd):
        return 280.0

    def _moon_longitude(self, jd):
        return 45.5

    def eclipse_details(self, sun, moon, jd):
        return {
            "solar_eclipse": False,
            "lunar_eclipse": True,
            "angular_separation": 125.5,
            "magnitude": 0.4,
            "type": "partial",
        }


@pytest.fixture
def chart_astro():
    return ChartAstro()


@pytest.mark.parametrize(
    "action,keys",
    [
        ("dasha", ("periods",)),
        ("ashtakavarga", ("rows",)),
        ("dignity", ("planets",)),
        ("aspects", ("aspects",)),
        ("nakshatra", ("nakshatra", "pada", "lord", "moon")),
        ("eclipse", ("solar_eclipse", "lunar_eclipse", "magnitude")),
    ],
)
def test_the_chart_sections_return_plain_data(chart_astro, action, keys):
    out = kundali_engine.compute_data(
        action,
        {
            "action": action,
            "datetime": "1990-01-01T12:00:00Z",
            "latitude": 28.6,
            "longitude": 77.2,
        },
        chart_astro,
    )
    assert "error" not in out
    for key in keys:
        assert key in out


def test_removed_calculations_are_not_guessed(chart_astro):
    for action in ("vimshopaka", "grahana", "bazi", "fullchart", "meanmotion"):
        out = kundali_engine.compute_data(
            action,
            {
                "action": action,
                "datetime": "1990-01-01T12:00:00Z",
                "latitude": 28.6,
                "longitude": 77.2,
            },
            chart_astro,
        )
        assert "error" in out


def test_the_cli_still_writes_json():
    out = subprocess.run(
        [
            sys.executable,
            str(ROOT / "bridge/kundali.py"),
            "panchang",
            "2024-01-01",
            "28.6",
            "77.2",
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 0
    assert out.stdout.strip().startswith("{")
    assert "Traceback" not in out.stderr
