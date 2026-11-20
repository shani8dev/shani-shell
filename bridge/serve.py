#!/usr/bin/env python3
"""serve — a folder opened to the phones and computers on this network, for a while
(ES File Explorer's "access from PC", the other way round): a web page any browser
reads, behind a link nobody can guess.

    serve.py <folder> [--upload]    prints {"url", "port"} once listening, then a
                                    {"got": name} line for each file a phone adds

http://<this computer>:<port>/<secret>/ lists the folder (its sub-folders too) and
hands out its files; anything without the secret is "not found". With --upload, a
phone can also add files (never over one that is there). Hidden files are not
shown, and nothing outside the folder is reachable - a link inside that points
out is not followed. It stops on SIGTERM, or after an hour nobody asked for
anything. The port is fixed (SHANI_SERVE_PORT, 53318) so the shell can open it in
the firewall for just that while.
"""

from __future__ import annotations

import html
import json
import os
import secrets
import signal
import socket
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("SHANI_SERVE_PORT", "53318"))
IDLE = int(os.environ.get("SHANI_SERVE_IDLE", "3600"))
MAX_UPLOAD = int(os.environ.get("SHANI_SERVE_MAX_UPLOAD", str(2 * 1024**3)))


def lan_address() -> str:
    """The address phones on this network reach: the one the route out leaves from
    (a UDP socket connected, nothing sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.0.2.1", 9))  # TEST-NET: never routed anywhere
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def safe_name(n: str) -> str:
    n = os.path.basename(n.replace("\\", "/")).strip()
    return "" if n in ("", ".", "..") or n.startswith(".") else n


def free_name(d: str, n: str) -> str:
    stem, ext = os.path.splitext(n)
    out, i = os.path.join(d, n), 2
    while os.path.lexists(out):
        out, i = os.path.join(d, "%s %d%s" % (stem, i, ext)), i + 1
    return out


PAGE = """<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>{title}</title><style>body{{font:16px system-ui,sans-serif;margin:0 auto;max-width:720px;padding:16px}}
a{{display:block;padding:12px 8px;border-bottom:1px solid #8884;text-decoration:none;color:inherit}}
small{{float:right;opacity:.6}}h1{{font-size:20px}}#up{{margin:16px 0;padding:12px;border:2px dashed #8888;border-radius:8px}}</style>
<h1>{title}</h1>{upload}{rows}"""
UPLOAD = """<div id=up><input type=file multiple id=f> <span id=s></span></div><script>
document.getElementById('f').onchange=async e=>{{const s=document.getElementById('s');
for(const f of e.target.files){{s.textContent='Sending '+f.name+'…';
const r=await fetch(location.pathname+encodeURIComponent(f.name),{{method:'PUT',body:f}});
s.textContent=r.ok?'Sent '+f.name:'Not sent: '+f.name}} setTimeout(()=>location.reload(),800)}}</script>"""


def make_handler(root: str, token: str, upload: bool, seen: list):
    root = os.path.realpath(root)

    class H(BaseHTTPRequestHandler):
        server_version = "shani-serve"

        def log_message(self, *a):
            pass

        def _where(self):
            """The real path asked for, inside root - or None."""
            path = urllib.parse.urlsplit(self.path).path
            if not path.startswith("/%s/" % token):
                return None
            rel = urllib.parse.unquote(path[len(token) + 2 :])
            if any(p.startswith(".") for p in rel.split("/") if p):
                return None
            real = os.path.realpath(os.path.join(root, rel))
            return real if real == root or real.startswith(root + os.sep) else None

        def _no(self, code=404):
            self.send_response(code)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_GET(self):
            seen[0] = time.monotonic()
            p = self._where()
            if p is None or not os.path.exists(p):
                return self._no()
            if os.path.isdir(p):
                if not urllib.parse.urlsplit(self.path).path.endswith("/"):
                    self.send_response(301)
                    self.send_header(
                        "Location", urllib.parse.urlsplit(self.path).path + "/"
                    )
                    self.end_headers()
                    return
                rows = []
                if p != root:
                    rows.append('<a href="../">↩ ..</a>')
                for de in sorted(
                    os.scandir(p), key=lambda d: (not d.is_dir(), d.name.lower())
                ):
                    if de.name.startswith("."):
                        continue
                    q = urllib.parse.quote(de.name) + ("/" if de.is_dir() else "")
                    size = (
                        ""
                        if de.is_dir()
                        else "<small>%s</small>" % human(de.stat().st_size)
                    )
                    rows.append(
                        '<a href="%s">%s%s%s</a>'
                        % (q, "📁 " if de.is_dir() else "", html.escape(de.name), size)
                    )
                body = PAGE.format(
                    title=html.escape(os.path.basename(p) or "/"),
                    upload=UPLOAD if upload else "",
                    rows="".join(rows) or "<p>Nothing here yet.</p>",
                ).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            size = os.path.getsize(p)
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header(
                "Content-Disposition",
                "attachment; filename*=UTF-8''"
                + urllib.parse.quote(os.path.basename(p)),
            )
            self.send_header("Content-Length", str(size))
            self.end_headers()
            with open(p, "rb") as f:
                while chunk := f.read(1 << 20):
                    self.wfile.write(chunk)

        def do_PUT(self):
            seen[0] = time.monotonic()
            if not upload:
                return self._no(403)
            path = urllib.parse.urlsplit(self.path).path
            d = self._where_dir(path)
            name = safe_name(urllib.parse.unquote(path.rsplit("/", 1)[-1]))
            if d is None or not name:
                return self._no(403)
            n = int(self.headers.get("Content-Length") or 0)
            # anyone on the LAN with the link can upload; bound it so a single
            # request cannot fill the disk
            if n > MAX_UPLOAD:
                return self._no(413)
            out = free_name(d, name)
            part = out + ".part"
            try:
                with open(part, "xb") as f:
                    while n > 0:
                        chunk = self.rfile.read(min(n, 1 << 20))
                        if not chunk:
                            break
                        f.write(chunk)
                        n -= len(chunk)
                if n:
                    raise OSError("cut short")
                os.rename(part, out)
            except OSError:
                try:
                    os.remove(part)  # only the half-sent file this request made
                except OSError:
                    pass
                return self._no(500)
            print(json.dumps({"got": out}), flush=True)
            self._no(201)

        def _where_dir(self, path):
            saved, self.path = self.path, path.rsplit("/", 1)[0] + "/"
            try:
                d = self._where()
            finally:
                self.path = saved
            return d if d and os.path.isdir(d) else None

    return H


def human(n: int) -> str:
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024 or u == "GB":
            return ("%d %s" if u == "B" else "%.1f %s") % (n, u)
        n /= 1024
    return str(n)


def main(argv: list[str]) -> int:
    args = argv[1:]
    upload = "--upload" in args
    args = [a for a in args if a != "--upload"]
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    token = secrets.token_urlsafe(12)
    seen = [time.monotonic()]
    try:
        srv = ThreadingHTTPServer(
            ("0.0.0.0", PORT), make_handler(args[0], token, upload, seen)
        )
    except OSError as e:
        print(json.dumps({"error": "port %d: %s" % (PORT, e.strerror)}), flush=True)
        return 1
    srv.daemon_threads = True
    signal.signal(
        signal.SIGTERM, lambda *_: threading.Thread(target=srv.shutdown).start()
    )

    def idle():
        while True:
            time.sleep(30)
            if time.monotonic() - seen[0] > IDLE:
                srv.shutdown()
                return

    threading.Thread(target=idle, daemon=True).start()
    print(
        json.dumps(
            {"url": "http://%s:%d/%s/" % (lan_address(), PORT, token), "port": PORT}
        ),
        flush=True,
    )
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
