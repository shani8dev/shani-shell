#!/usr/bin/env python3
"""fake-greetd — the greetd end of the greeter's socket, for driving the greeter.

Speaks greetd's IPC (u32 native-endian length + JSON, one request -> one
response) on $GREETD_SOCK, and prints every request it receives as one JSON line
so a test can assert the exact conversation. It authenticates one account:

  user "shani", password "shani"   -> success, start_session accepted
  user "otp"                       -> password, then a second visible prompt
                                      ("Code:"), answer "123456"
  anything else                    -> auth_error

Nothing is started: start_session is only recorded.
"""

from __future__ import annotations

import json
import os
import socket
import struct
import sys

SOCK = os.environ.get("GREETD_SOCK") or sys.exit("GREETD_SOCK is not set")


def send(conn: socket.socket, msg: dict) -> None:
    data = json.dumps(msg).encode()
    conn.sendall(struct.pack("=I", len(data)) + data)


def recv(conn: socket.socket) -> dict | None:
    head = conn.recv(4, socket.MSG_WAITALL)
    if len(head) < 4:
        return None
    (n,) = struct.unpack("=I", head)
    return json.loads(conn.recv(n, socket.MSG_WAITALL))


def serve(conn: socket.socket) -> None:
    user = None
    prompts: list[tuple[str, str, str]] = []  # (type, text, expected answer)
    while (req := recv(conn)) is not None:
        print(json.dumps(req), flush=True)
        kind = req.get("type")
        if kind == "create_session":
            user = req.get("username")
            prompts = [("secret", "Password:", user if user == "shani" else "otp")]
            if user == "otp":
                prompts.append(("visible", "Code:", "123456"))
            send(conn, {"type": "auth_message", "auth_message_type": prompts[0][0],
                        "auth_message": prompts[0][1]})
        elif kind == "post_auth_message_response":
            if user not in ("shani", "otp") or req.get("response") != prompts[0][2]:
                user, prompts = None, []
                send(conn, {"type": "error", "error_type": "auth_error",
                            "description": "Authentication failed"})
                continue
            prompts.pop(0)
            if prompts:
                send(conn, {"type": "auth_message", "auth_message_type": prompts[0][0],
                            "auth_message": prompts[0][1]})
            else:
                send(conn, {"type": "success"})
        elif kind == "start_session":
            send(conn, {"type": "success"})
        elif kind == "cancel_session":
            user, prompts = None, []
            send(conn, {"type": "success"})
        else:
            send(conn, {"type": "error", "error_type": "error",
                        "description": f"unknown request {kind!r}"})


def main() -> int:
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)
    srv.listen(4)
    print(json.dumps({"type": "fake-greetd-up", "sock": SOCK}), flush=True)
    while True:
        conn, _ = srv.accept()
        with conn:
            serve(conn)


if __name__ == "__main__":
    sys.exit(main())
