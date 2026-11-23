#!/usr/bin/env python3
"""A stand-in for MailHog in the test slot: the two messages the shell's mail
reader expects, over the same HTTP API, plus an SMTP sink on 1025 that records
what was sent to /tmp/mail-sent.

    python3 fake-mailhog.py [port]

MailHog's API is /api/v2/messages (list) and /api/v2/messages/<id> (one).

An attachment is listed as {Name, Content-Type, Size} and carries its raw bytes
base64 in "Content" - the same way the API's MIME field carries the message
itself - so the reader can decode it and save it (readme.txt below).
"""

import base64
import json
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

README = b"Shani shell readme.\n"

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
            "HTML": '<p>Thanks for installing <b>ShaniOS</b>.</p><p><img src="http://tracker.example/p.gif"></p>',
            "Attachments": [
                {
                    "Name": "readme.txt",
                    "Content-Type": "text/plain",
                    "Size": len(README),
                    "Content": base64.b64encode(README).decode("ascii"),
                }
            ],
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


def stored(raw):
    """A message that came in over SMTP, in the shape the HTTP API serves.

    Only what the reader shows: the sender as a person reads it, the subject,
    and the text. The API's own list keeps a snippet; this one keeps the text.
    """
    import email
    from email.header import decode_header, make_header

    m = email.message_from_bytes(raw)
    headers = m

    def dec(v):
        try:
            return str(make_header(decode_header(v or "")))
        except Exception:
            return v or ""

    text = ""
    if m.is_multipart():
        for part in m.walk():
            if part.get_content_type() == "text/plain":
                text += part.get_payload(decode=True).decode(
                    part.get_content_charset() or "utf-8", "replace"
                )
    else:
        text = m.get_payload(decode=True).decode(
            m.get_content_charset() or "utf-8", "replace"
        )
    frm = dec(m.get("From", ""))
    name, _, addr = frm.rpartition("<")
    name = name.strip().strip('"')
    addr = addr.rstrip(">").strip()
    mid = "smtp-%d" % (len(MESSAGES) + 1)
    return {
        "ID": mid,
        "From": {"Name": name, "Address": addr or frm.strip()},
        "To": [{"Name": "", "Address": dec(m.get("To", ""))}],
        "Subject": dec(m.get("Subject", "")) or "(no subject)",
        "Date": m.get("Date", ""),
        "Size": len(raw),
        "Content": {
            "Headers": {
                "From": [frm],
                "To": [dec(m.get("To", ""))],
                "Subject": [dec(m.get("Subject", ""))],
                "Date": [m.get("Date", "")],
            },
            "Body": text,
            "Text": text,
        },
    }


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
        """Line by line, from a buffer: a client sends DATA and its message in
        one go, and reading "one recv == one line" would sit waiting for a reply
        the client is already waiting for itself."""
        buf = b""
        data_mode = False
        body = []
        with conn:
            conn.sendall(b"220 fake-mailhog ESMTP\r\n")
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    return
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if data_mode:
                        if line.strip() == b".":
                            data_mode = False
                            raw = b"".join(body)
                            with open("/tmp/mail-sent", "ab") as fh:
                                fh.write(raw + b"\n---\n")
                            body = []
                            MESSAGES.append(stored(raw))
                            conn.sendall(b"250 OK\r\n")
                        else:
                            body.append(line + b"\n")
                        continue
                    line = line.decode(errors="replace").strip()
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
