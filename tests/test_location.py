"""bridge/location.py against a fake gpsd: a fix wins; no fix, or no gpsd, falls through."""
import json, os, socket, subprocess, sys, threading

BRIDGE = os.path.join(os.path.dirname(__file__), "..", "bridge", "location.py")


def fake_gpsd(lines):
    srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1)
    def serve():
        c, _ = srv.accept()
        c.recv(256)                       # the ?WATCH request
        for l in lines:
            c.sendall((json.dumps(l) + "\n").encode())
        c.close(); srv.close()
    threading.Thread(target=serve, daemon=True).start()
    return srv.getsockname()[1]


def run(port):
    # never the real GeoClue: the fall-through ends at "not installed"
    env = dict(os.environ, SHANI_GPSD="127.0.0.1:%d" % port, SHANI_WHERE_AM_I="/nonexistent")
    out = subprocess.run([sys.executable, BRIDGE], capture_output=True, text=True, env=env, timeout=30)
    return json.loads(out.stdout)


def test_gpsd_fix_wins():
    port = fake_gpsd([{"class": "VERSION"}, {"class": "TPV", "mode": 1},
                      {"class": "TPV", "mode": 3, "lat": 18.52, "lon": 73.85, "epx": 6.5, "epy": 8.0}])
    r = run(port)
    assert r["source"] == "gpsd" and r["lat"] == 18.52 and r["lon"] == 73.85 and r["accuracy"] == 8.0


def test_no_fix_falls_through():
    port = fake_gpsd([{"class": "VERSION"}, {"class": "TPV", "mode": 1}])
    r = run(port)
    assert r.get("source") != "gpsd"


def test_no_gpsd_falls_through():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    r = run(port)
    assert r.get("source") != "gpsd"
