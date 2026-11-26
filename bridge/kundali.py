#!/usr/bin/env python3
"""Kundali / Panchang calculator for the shell's Kundali window.

    kundali.py panchang DATE LAT LON
    kundali.py kundali DATETIME LAT LON
    kundali.py details SECTION DATETIME LAT LON
        SECTION is dasha | ashtakavarga | dignity | aspects | nakshatra | eclipse

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
    value = str(value or "").strip()
    if "T" not in value:
        return value + "T12:00:00Z"
    return value if value.endswith("Z") else value + "Z"


def panchang(date_str, lat, lon):
    astro = _astro()
    if astro is None:
        return {"error": "Astronomy module not available"}
    stamp = _stamp(date_str)
    result = astro.compute_panchang(stamp, lat, lon)
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
    }
    if action not in names:
        print(json.dumps({"error": "usage: kundali.py <panchang|kundali|details> ..."}))
        return 2
    required = names[action]
    if len(argv) < 2 + len(required):
        print(json.dumps({"error": "missing " + ", ".join(required[len(argv) - 2 :])}))
        return 2
    try:
        if action == "details":
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
        else:
            result = details(section, when, lat, lon)
    except Exception as exc:  # noqa: BLE001 - never a traceback to the UI
        result = {"error": f"{type(exc).__name__}: {exc}"}
    print(json.dumps(result, ensure_ascii=False, default=str))
    return 1 if isinstance(result, dict) and result.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
