#!/usr/bin/env python3
"""Kundali / Panchang calculator for the shell's Kundali window.

    kundali.py panchang DATE LAT LON
    kundali.py kundali DATETIME LAT LON
    kundali.py details SECTION DATETIME LAT LON
        SECTION is dasha | ashtakavarga | dignity | aspects | nakshatra | eclipse
    kundali.py run ACTION DATETIME LAT LON [HOUSE]
        any of the engine's calculations (kundali_engine.ACTIONS), as text
    kundali.py actions
        the calculations, with what each needs

DATETIME is a UTC stamp (…Z) or a clock time where the birth was:
"1990-01-01T10:00@Asia/Kolkata" - converted with that zone's rules that day.

One JSON object on stdout. Every argument is required: a missing date or place
is an error, never New Delhi on 2024-01-01. The six sections return plain data
for the window to translate and draw.
"""

import json
import sys

import astronomy
import kundali_engine

SECTIONS = kundali_engine.SECTIONS


def _astro():
    """The local astronomy module (no Chronoa path shim)."""
    return astronomy


def _stamp(value: str) -> str:
    return kundali_engine.utc_instant(value)


#: actions that take a zodiac longitude: the Moon's
_MOON_LONGITUDE = ("nakshatra", "lunarmansion")
#: actions about one planet: every planet in the chart
_PER_PLANET = ("dignity", "meanmotion")
#: the Chinese systems count from the birth's own wall clock
_LOCAL_PARTS = ("bazi", "ziwei")


def run(action, when, lat, lon, house=None):
    """One of the engine's calculations for a birth, as {"text": ...}."""
    action = str(action or "").strip().lower()
    if action not in kundali_engine.ACTIONS:
        return {"error": f"Unknown calculation: {action}"}
    stamp = _stamp(when)
    args = {"action": action, "datetime": stamp, "date": stamp, "latitude": lat, "longitude": lon}
    if house:
        args["quesited_house"] = int(house)
    if action in _LOCAL_PARTS:
        args.update(kundali_engine.local_parts(when))
    if action in _MOON_LONGITUDE or action in _PER_PLANET:
        chart = astronomy.compute_chart(stamp, lat, lon)
        if action in _MOON_LONGITUDE:
            moon = next(p for p in chart["planets"] if p["name"] == "Moon")
            return {"text": kundali_engine.compute(dict(args, longitude=moon["sidereal_longitude"]), astronomy)}
        lines = [kundali_engine.compute(dict(args, planet=p["name"], sign=p["sign"]), astronomy)
                 for p in chart["planets"]]
        return {"text": "\n".join(lines)}
    return {"text": kundali_engine.compute(args, astronomy)}


def panchang(date_str, lat, lon):
    astro = _astro()
    if astro is None:
        return {"error": "Astronomy module not available"}
    stamp = _stamp(date_str)
    # the full panchang: the five limbs and the month, paksha, season and eras
    full = getattr(astro, "compute_full_panchang", None)
    result = full(stamp, lat, lon) if full else astro.compute_panchang(stamp, lat, lon)
    result["text"] = kundali_engine.compute(
        {
            "action": "panchang",
            "date": stamp,
            "latitude": lat,
            "longitude": lon,
        },
        astro,
    )
    return result


def kundali(datetime_str, lat, lon):
    astro = _astro()
    if astro is None:
        return {"error": "Astronomy module not available"}
    stamp = _stamp(datetime_str)
    chart = astro.compute_full_chart_v2(stamp, lat, lon)
    # every planet's navamsa (D9) sign, for the window's D1 / D9 chart
    if hasattr(astro, "varga_longitude") and "ascendant" in chart:
        chart["navamsa"] = [
            {"name": p["name"], "sign": astro.SIGNS[int(astro.varga_longitude(p["sidereal_longitude"], "D9") / 30) % 12]}
            for p in chart.get("planets", [])
        ]
        chart["navamsa_ascendant"] = astro.SIGNS[int(astro.varga_longitude(chart["ascendant"], "D9") / 30) % 12]
        # every divisional chart: the ascendant's and each planet's sign
        sign = lambda lon, d: astro.SIGNS[int(astro.varga_longitude(lon, d) / 30) % 12]
        chart["vargas_all"] = {
            d: {"ascendant": sign(chart["ascendant"], d),
                "planets": {p["name"]: sign(p["sidereal_longitude"], d) for p in chart.get("planets", [])}}
            for d in ("D1", "D2", "D3", "D4", "D7", "D9", "D10", "D12", "D16", "D20", "D24", "D27", "D30", "D40", "D45", "D60")
        }
    chart["text"] = kundali_engine.compute(
        {
            "action": "kundali",
            "datetime": stamp,
            "latitude": lat,
            "longitude": lon,
        },
        astro,
    )
    return chart


def details(section, datetime_str, lat, lon):
    """One chart section, as data with stable keys."""
    astro = _astro()
    if astro is None:
        return {"error": "Astronomy module not available"}
    section = str(section or "").strip().lower()
    if section not in SECTIONS:
        return {"error": f"Unknown section: {section}"}
    return kundali_engine.compute_data(
        section,
        {
            "action": section,
            "datetime": _stamp(datetime_str),
            "latitude": lat,
            "longitude": lon,
        },
        astro,
    )


def main(argv: list[str]) -> int:
    action = str(argv[1] if len(argv) > 1 else "").strip().lower()
    names = {
        "panchang": ("date", "latitude", "longitude"),
        "kundali": ("datetime", "latitude", "longitude"),
        "details": ("section", "datetime", "latitude", "longitude"),
        "run": ("calculation", "datetime", "latitude", "longitude"),
        "actions": (),
    }
    if action not in names:
        print(json.dumps({"error": "usage: kundali.py <panchang|kundali|details> ..."}))
        return 2
    required = names[action]
    if len(argv) < 2 + len(required):
        print(json.dumps({"error": "missing " + ", ".join(required[len(argv) - 2 :])}))
        return 2
    if action == "actions":
        print(json.dumps({"actions": kundali_engine.ACTIONS}, ensure_ascii=False))
        return 0
    try:
        if action in ("details", "run"):
            section = argv[2]
            when, lat, lon = argv[3], float(argv[4]), float(argv[5])
        else:
            section = ""
            when, lat, lon = argv[2], float(argv[3]), float(argv[4])
    except ValueError:
        print(json.dumps({"error": "latitude and longitude must be numbers"}))
        return 2
    try:
        if action == "panchang":
            result = panchang(when, lat, lon)
        elif action == "kundali":
            result = kundali(when, lat, lon)
            try:
                result["aspects"] = _astro().compute_aspects(result.get("planets", []))
            except Exception:
                pass
        elif action == "run":
            result = run(section, when, lat, lon, argv[6] if len(argv) > 6 else None)
        else:
            result = details(section, when, lat, lon)
    except Exception as exc:  # noqa: BLE001 - never a traceback to the UI
        result = {"error": f"{type(exc).__name__}: {exc}"}
    print(json.dumps(result, ensure_ascii=False, default=str))
    return 1 if isinstance(result, dict) and result.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
