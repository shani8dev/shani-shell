#!/usr/bin/env python3
"""shani-shell location helper: where the computer is, as one JSON object
{"lat", "lon", "accuracy", "source"} (accuracy in metres) or {"error": "..."}.

First gpsd, when it runs and has a fix: a GPS receiver (a USB dongle, a
phone's NMEA, a WWAN modem) is the most exact source there is, and GeoClue
cannot read gpsd. Then GeoClue2 (Wi-Fi, the modem's GPS, IP), which decides
itself what it may tell.

It asks through GeoClue's own client, where-am-i, which GeoClue's default
configuration lets ask without a desktop agent. No agent is started: GeoClue's
demo agent would approve every app's request while it ran. Failure (no
GeoClue, no network or GPS, the request refused) is "location unavailable",
and the shell keeps the typed city.
"""
import json, os, socket, subprocess, time

WHERE = os.environ.get("SHANI_WHERE_AM_I") or "/usr/lib/geoclue-2.0/demos/where-am-i"

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

def via_gpsd(wait=4.0):
    """A fix from gpsd (localhost:2947, or SHANI_GPSD=host:port): the first
    TPV report with a 2D or 3D fix; None when gpsd is not there or has none."""
    host, _, port = (os.environ.get("SHANI_GPSD") or "127.0.0.1:2947").partition(":")
    try:
        s = socket.create_connection((host, int(port or 2947)), timeout=1.0)
    except OSError:
        return None
    end = time.time() + wait
    buf = b""
    try:
        s.sendall(b'?WATCH={"enable":true,"json":true};\n')
        while time.time() < end:
            s.settimeout(max(0.1, end - time.time()))
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("class") == "TPV" and r.get("mode", 0) >= 2 and "lat" in r and "lon" in r:
                    acc = max(r.get("epx") or 0, r.get("epy") or 0) or r.get("eph") or 0
                    return {"lat": r["lat"], "lon": r["lon"], "accuracy": acc, "source": "gpsd"}
    finally:
        s.close()
    return None

def main():
    fix = via_gpsd()
    if fix:
        print(json.dumps(fix))
        return
    if not os.path.exists(WHERE):
        print(json.dumps({"error": "no GPS fix from gpsd, and GeoClue is not installed"}))
        return
    r = via_where_am_i()
    if r and "error" not in r:
        r["source"] = "geoclue"
    print(json.dumps(r))

if __name__ == "__main__":
    main()