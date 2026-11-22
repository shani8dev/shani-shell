#!/usr/bin/env python3
"""A stand-in for MailHog in the test slot: the two messages the shell's mail
reader expects, over the same HTTP API, plus an SMTP sink on 1025 that records
what was sent to /tmp/mail-sent.

    python3 fake-mailhog.py [port]

MailHog's API is /api/v2/messages (list) and /api/v2/messages/<id> (one).
"""

import json
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MESSAGES = [
    {
        "ID": "mail-1",
        "From": {"Name": "Shani Team", "Address": "team@example.com"},
        "To": [{"Name": "Shani Tester", "Address": "shani@example.com"}],
        "Subject": "Welcome to Shani",
        "Date": "Sat, 21 Nov 2026 09:00:00 +0000",
        "Size": 412,
        "Content": {
            "Headers": {
                "From": ["Shani Team <team@example.com>"],
                "To": ["shani@example.com"],
                "Subject": ["Welcome to Shani"],
                "Date": ["Sat, 21 Nov 2026 09:00:00 +0000"],
            },
            "Body": "Thanks for installing ShaniOS.",
            "Text": "Thanks for installing ShaniOS.\n\nReply to this message to say hello.",
            "HTML": "<p>Thanks for installing ShaniOS.</p>",
        },
    },
    {
        "ID": "mail-2",
        "From": {"Name": "Niri", "Address": "niri@example.com"},
        "To": [{"Name": "Shani Tester", "Address": "shani@example.com"}],
        "Subject": "Your layouts are ready",
        "Date": "Fri, 20 Nov 2026 18:30:00 +0000",
        "Size": 280,
        "Content": {
            "Headers": {
                "From": ["Niri <niri@example.com>"],
                "To": ["shani@example.com"],
                "Subject": ["Your layouts are ready"],
                "Date": ["Fri, 20 Nov 2026 18:30:00 +0000"],
            },
            "Body": "Three layouts were generated for this screen.",
            "Text": "Three layouts were generated for this screen.",
            "HTML": "<p>Three layouts were generated for this screen.</p>",
        },
    },
]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/v2/messages":
            self._json(
                {
                    "total": len(MESSAGES),
                    "count": len(MESSAGES),
                    "start": 0,
                    "messages": MESSAGES,
                }
            )
        elif path.startswith("/api/v2/messages/"):
            mid = path.rsplit("/", 1)[-1]
            for m in MESSAGES:
                if m["ID"] == mid:
                    self._json(m)
                    return
            self._json({"error": "not found"}, 404)
        else:
            self._json({"error": "unknown path"}, 404)


def smtp_sink(port=1025):
    """Enough of SMTP to accept a message: 220, EHLO, MAIL, RCPT, DATA, ."""
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(5)

    def serve():
        while True:
            try:
                conn, _ = srv.accept()
            except OSError:
                return
            threading.Thread(target=handle, args=(conn,), daemon=True).start()

    def handle(conn):
        data_mode = False
        body = []
        with conn:
            conn.sendall(b"220 fake-mailhog ESMTP\r\n")
            while True:
                buf = b""
                while not buf.endswith(b"\n"):
                    chunk = conn.recv(4096)
                    if not chunk:
                        return
                    buf += chunk
                if data_mode:
                    if buf.strip() == b".":
                        data_mode = False
                        with open("/tmp/mail-sent", "ab") as fh:
                            fh.write(b"".join(body) + b"\n---\n")
                        body = []
                        conn.sendall(b"250 OK\r\n")
                    else:
                        body.append(buf)
                    continue
                line = buf.decode(errors="replace").strip()
                upper = line.upper()
                if upper.startswith("EHLO") or upper.startswith("HELO"):
                    conn.sendall(b"250-fake-mailhog\r\n250 OK\r\n")
                elif upper.startswith("MAIL") or upper.startswith("RCPT"):
                    conn.sendall(b"250 OK\r\n")
                elif upper == "DATA":
                    data_mode = True
                    conn.sendall(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                elif upper == "QUIT":
                    conn.sendall(b"221 Bye\r\n")
                    return
                else:
                    conn.sendall(b"250 OK\r\n")

    threading.Thread(target=serve, daemon=True).start()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8025
    smtp_sink()
    http = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("fake-mailhog on %d" % port, flush=True)
    http.serve_forever()
