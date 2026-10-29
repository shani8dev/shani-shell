#!/usr/bin/env python3
"""shani-shell location helper: ask GeoClue2 where the computer is, print one JSON
object {"lat", "lon", "accuracy"} (metres) or {"error": "..."}.

It asks through GeoClue's own client, where-am-i, which GeoClue's default
configuration lets ask without a desktop agent. No agent is started: GeoClue's
demo agent would approve every app's request while it ran. Failure (no
GeoClue, no network or GPS, the request refused) is "location unavailable",
and the shell keeps the typed city.
"""
import json, os, subprocess

WHERE = "/usr/lib/geoclue-2.0/demos/where-am-i"

def via_where_am_i():
    if not os.path.exists(WHERE):
        return None
    try:
        out = subprocess.run([WHERE], capture_output=True, text=True, timeout=20)
        txt = out.stdout + out.stderr
    except Exception as e:
        return {"error": str(e)}
    lat = lon = acc = None
    for line in txt.splitlines():
        low = line.lower()
        if "latitude" in low:
            try: lat = float(line.split(":")[-1])
            except ValueError: pass
        elif "longitude" in low:
            try: lon = float(line.split(":")[-1])
            except ValueError: pass
        elif "accuracy" in low:
            try: acc = float(line.split(":")[-1].split()[0])
            except (ValueError, IndexError): pass
    if lat is not None and lon is not None:
        return {"lat": lat, "lon": lon, "accuracy": acc or 0}
    return {"error": "no location in where-am-i output", "raw": txt.strip()[:300]}

def main():
    if not os.path.exists(WHERE):
        print(json.dumps({"error": "GeoClue is not installed"}))
        return
    print(json.dumps(via_where_am_i()))

if __name__ == "__main__":
    main()