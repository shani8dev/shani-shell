#!/usr/bin/env python3
"""A stand-in for OpenStreetMap's tile server, Nominatim and OSRM, for the
offline test session (dev/shell-parts/maps.sh): tiles are coloured squares
(a colour per x/y), a search for anything finds one place, and a route is a
three-point line with two steps - each in the services' own JSON shape."""
import json
import struct
import sys
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def png(w: int, h: int, rgb: tuple) -> bytes:
    """A plain-coloured PNG with a white border, written by hand (no Pillow here)."""
    border = bytes((255, 255, 255))
    fill = bytes(rgb)
    rows = b"".join(b"\0" + (border * w if y in (0, h - 1) else border + fill * (w - 2) + border) for y in range(h))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")

PLACES = {"pune station": ("18.5289", "73.8744", "Pune Railway Station, Pune, India"),
          "shaniwar wada": ("18.5195", "73.8553", "Shaniwar Wada, Pune, India")}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, body: bytes, kind: str):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path.startswith("/tiles/"):
            z, x, y = path[len("/tiles/"):].removesuffix(".png").split("/")
            self.send(png(256, 256, ((int(x) * 40) % 200 + 40, (int(y) * 60) % 200 + 40, 150)), "image/png")
        elif path == "/search":
            q = self.path.split("q=", 1)[-1].replace("+", " ").replace("%20", " ").lower()
            hit = next((v for k, v in PLACES.items() if k in q), None)
            rows = [{"lat": hit[0], "lon": hit[1], "display_name": hit[2], "type": "station"}] if hit else []
            self.send(json.dumps(rows).encode(), "application/json")
        elif path.startswith("/route/v1/"):
            coords = path.split("/")[-1].split(";")
            (lon1, lat1), (lon2, lat2) = [tuple(map(float, c.split(","))) for c in coords]
            mid = [(lon1 + lon2) / 2, lat1]
            route = {"code": "Ok", "routes": [{"distance": 2450.0, "duration": 540.0,
                     "geometry": {"type": "LineString", "coordinates": [[lon1, lat1], mid, [lon2, lat2]]},
                     "legs": [{"steps": [
                         {"name": "Station Road", "distance": 1200, "maneuver": {"type": "depart"}},
                         {"name": "Shivaji Road", "distance": 1250, "maneuver": {"type": "turn", "modifier": "left"}},
                         {"name": "", "distance": 0, "maneuver": {"type": "arrive"}}]}]}]}
            self.send(json.dumps(route).encode(), "application/json")
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8797), Handler).serve_forever()
