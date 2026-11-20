#!/usr/bin/env python3
"""A stand-in for radio-browser.info for the offline test session
(dev/shell-parts/radio.sh): three stations in the directory's own JSON shape,
whose streams are a short tone served from here (WAV, endless enough), and the
play-count URL it asks apps to call (counted, so the suite can see it)."""
import io
import json
import math
import struct
import sys
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8798
COUNTED = []


def tone(seconds=60):
    buf = io.BytesIO()
    w = wave.open(buf, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(b"".join(struct.pack("<h", int(6000 * math.sin(2 * math.pi * 440 * i / 16000))) for i in range(16000 * seconds)))
    return buf.getvalue()


TONE = tone()
STATIONS = [
    {"stationuuid": "u-akashvani", "name": "Akashvani Pune", "url_resolved": "http://127.0.0.1:%d/stream/1.wav" % PORT, "favicon": "",
     "tags": "news,talk", "countrycode": "IN", "codec": "WAV", "bitrate": 256, "clickcount": 900},
    {"stationuuid": "u-jazz", "name": "Night Jazz", "url_resolved": "http://127.0.0.1:%d/stream/2.wav" % PORT, "favicon": "",
     "tags": "jazz", "countrycode": "FR", "codec": "WAV", "bitrate": 256, "clickcount": 500},
    {"stationuuid": "u-bolly", "name": "Bollywood Hits", "url_resolved": "http://127.0.0.1:%d/stream/3.wav" % PORT, "favicon": "",
     "tags": "bollywood,pop", "countrycode": "IN", "codec": "WAV", "bitrate": 256, "clickcount": 700},
]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, body, kind):
        self.send_response(200); self.send_header("Content-Type", kind); self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path
        if p.startswith("/stream/"):
            return self.send(TONE, "audio/wav")
        if p.startswith("/json/url/"):
            COUNTED.append(p.rsplit("/", 1)[1]); open("/tmp/fake-radio-counted", "a").write(p.rsplit("/", 1)[1] + "\n")
            return self.send(b'{"ok": true}', "application/json")
        if p.startswith("/json/stations/topclick"):
            out = sorted(STATIONS, key=lambda s: -s["clickcount"])
        elif p.startswith("/json/stations/bycountrycodeexact/IN"):
            out = [s for s in STATIONS if s["countrycode"] == "IN"]
        elif p.startswith("/json/stations/bytagexact/"):
            tag = p.split("/")[-1].split("?")[0]
            out = [s for s in STATIONS if tag in s["tags"].split(",")]
        elif p.startswith("/json/stations/search"):
            q = p.split("name=")[1].split("&")[0].lower() if "name=" in p else ""
            out = [s for s in STATIONS if q in s["name"].lower()]
        else:
            out = []
        self.send(json.dumps(out).encode(), "application/json")


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
