#!/usr/bin/env python3
"""Kundali/Panchang calculator for ShaniOS shell.

Pure Python — no external dependencies (uses shani-chronoa astronomy module).

Usage:
  kundali.py panchang DATE LAT LON
  kundali.py kundali DATETIME LAT LON

Outputs JSON to stdout.
"""
import json
import os
import sys


def _astro():
    """Import the astronomy module from chronoa."""
    paths = [
        "/usr/lib/shani-chronoa",
        os.path.expanduser("~/.local/lib/python3.14/site-packages"),
        os.path.expanduser("~/Documents/shani/shani-chronoa/usr/lib/shani-chronoa"),
    ]
    for p in paths:
        if p not in sys.path:
            sys.path.insert(0, p)
    try:
        from shani_chronoa import astronomy
        return astronomy
    except ImportError:
        import importlib.util
        for base in ["/usr/lib/shani-chronoa/shani_chronoa",
                     os.path.expanduser("~/Documents/shani/shani-chronoa/usr/lib/shani-chronoa/shani_chronoa")]:
            mod_path = os.path.join(base, "astronomy.py")
            if os.path.isfile(mod_path):
                spec = importlib.util.spec_from_file_location("astronomy", mod_path)
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                return mod
    return None


def panchang(date_str, lat, lon):
    astro = _astro()
    if astro is None:
        return {"error": "Astronomy module not available"}
    if "T" not in date_str:
        date_str = date_str + "T12:00:00Z"
    elif not date_str.endswith("Z"):
        date_str = date_str + "Z"
    return astro.compute_panchang(date_str, lat, lon)


def kundali(datetime_str, lat, lon):
    astro = _astro()
    if astro is None:
        return {"error": "Astronomy module not available"}
    if "T" not in datetime_str:
        datetime_str = datetime_str + "T12:00:00Z"
    elif not datetime_str.endswith("Z"):
        datetime_str = datetime_str + "Z"
    chart = astro.compute_full_chart_v2(datetime_str, lat, lon)
    return chart


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "panchang"
    if action == "panchang":
        date = sys.argv[2] if len(sys.argv) > 2 else "2024-01-01"
        lat = float(sys.argv[3]) if len(sys.argv) > 3 else 28.6139
        lon = float(sys.argv[4]) if len(sys.argv) > 4 else 77.2090
        print(json.dumps(panchang(date, lat, lon), ensure_ascii=False))
    elif action == "kundali":
        dt = sys.argv[2] if len(sys.argv) > 2 else "1990-01-01T12:00:00Z"
        lat = float(sys.argv[3]) if len(sys.argv) > 3 else 28.6139
        lon = float(sys.argv[4]) if len(sys.argv) > 4 else 77.2090
        result = kundali(dt, lat, lon)
        # Add aspects
        try:
            astro = _astro()
            aspects = astro.compute_aspects(result.get("planets", []))
            result["aspects"] = aspects
        except Exception:
            pass
        print(json.dumps(result, ensure_ascii=False))
    elif action == "nakshatra":
        lon = float(sys.argv[2]) if len(sys.argv) > 2 else 0
        astro = _astro()
        if astro:
            print(json.dumps(astro.nakshatra_details(lon), ensure_ascii=False))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    elif action == "aspects":
        date = sys.argv[2] if len(sys.argv) > 2 else "2024-01-01"
        lat = float(sys.argv[3]) if len(sys.argv) > 3 else 28.6139
        lon = float(sys.argv[4]) if len(sys.argv) > 4 else 77.2090
        if "T" not in date:
            date = date + "T12:00:00Z"
        astro = _astro()
        if astro:
            chart = astro.compute_full_chart_v2(date, lat, lon)
            aspects = astro.compute_aspects(chart["planets"])
            print(json.dumps({"aspects": aspects}, ensure_ascii=False))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    elif action == "dignity":
        planet = sys.argv[2] if len(sys.argv) > 2 else "Sun"
        sign = sys.argv[3] if len(sys.argv) > 3 else "Aries"
        astro = _astro()
        if astro:
            print(json.dumps(astro.planet_info(planet, sign), ensure_ascii=False))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    elif action == "transit":
        date = sys.argv[2] if len(sys.argv) > 2 else "2024-01-01"
        lat = float(sys.argv[3]) if len(sys.argv) > 3 else 28.6139
        lon = float(sys.argv[4]) if len(sys.argv) > 4 else 77.2090
        # Need natal planets - compute from a birth date
        birth = sys.argv[5] if len(sys.argv) > 5 else None
        astro = _astro()
        if astro:
            if "T" not in date:
                date = date + "T12:00:00Z"
            chart = astro.compute_full_chart_v2(date, lat, lon)
            natal_planets = []
            if birth:
                natal_chart = astro.compute_full_chart_v2(birth, lat, lon)
                natal_planets = natal_chart.get("planets", [])
            result = astro.transit_chart(natal_planets, date, lat, lon)
            print(json.dumps(result, ensure_ascii=False, default=str))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    elif action == "timelords":
        dt = sys.argv[2] if len(sys.argv) > 2 else "1990-01-01T12:00:00Z"
        lat = float(sys.argv[3]) if len(sys.argv) > 3 else 28.6139
        lon = float(sys.argv[4]) if len(sys.argv) > 4 else 77.2090
        astro = _astro()
        if astro:
            if "T" not in dt:
                dt = dt + "T12:00:00Z"
            chart = astro.compute_full_chart(dt, lat, lon)
            tl = astro.time_lords(dt, chart["ascendant"], 0, 10)
            print(json.dumps(tl, ensure_ascii=False, default=str))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    elif action == "arabicparts":
        dt = sys.argv[2] if len(sys.argv) > 2 else "1990-01-01T12:00:00Z"
        lat = float(sys.argv[3]) if len(sys.argv) > 3 else 28.6139
        lon = float(sys.argv[4]) if len(sys.argv) > 4 else 77.2090
        astro = _astro()
        if astro:
            if "T" not in dt:
                dt = dt + "T12:00:00Z"
            chart = astro.compute_full_chart(dt, lat, lon)
            asc = chart["ascendant"]
            sun = next((pp for pp in chart["planets"] if pp["name"] == "Sun"), {})
            moon = next((pp for pp in chart["planets"] if pp["name"] == "Moon"), {})
            parts = astro.arabic_parts(asc, sun.get("sidereal_longitude", 0), moon.get("sidereal_longitude", 0))
            print(json.dumps(parts, ensure_ascii=False))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    elif action == "temperament":
        dt = sys.argv[2] if len(sys.argv) > 2 else "1990-01-01T12:00:00Z"
        lat = float(sys.argv[3]) if len(sys.argv) > 3 else 28.6139
        lon = float(sys.argv[4]) if len(sys.argv) > 4 else 77.2090
        astro = _astro()
        if astro:
            if "T" not in dt:
                dt = dt + "T12:00:00Z"
            chart = astro.compute_full_chart(dt, lat, lon)
            temp = astro.temperament(chart["planets"])
            print(json.dumps(temp, ensure_ascii=False))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    elif action == "lunarmansion":
        lon = float(sys.argv[2]) if len(sys.argv) > 2 else 0
        astro = _astro()
        if astro:
            print(json.dumps({"mansion": astro.lunar_mansion(lon)}, ensure_ascii=False))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    elif action == "bazi":
        year = int(sys.argv[2]) if len(sys.argv) > 2 else 2024
        month = int(sys.argv[3]) if len(sys.argv) > 3 else 1
        day = int(sys.argv[4]) if len(sys.argv) > 4 else 1
        hour = int(sys.argv[5]) if len(sys.argv) > 5 else 12
        astro = _astro()
        if astro:
            print(json.dumps(astro.bazi_pillars(year, month, day, hour), ensure_ascii=False))
        else:
            print(json.dumps({"error": "Astronomy module not available"}))
    else:
        print(json.dumps({"error": f"Unknown action: {action}"}))
