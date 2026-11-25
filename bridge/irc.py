#!/usr/bin/env python3
"""irc — the shell's minimal IRC client, as a long-running Process.

    python3 irc.py            runs while the IRC window is open (stdin stays open)

stdin, one JSON object a line, from Services/Irc:
    {"op":"connect","server":"irc.libera.chat","port":6697,"nick":"shani","tls":true}
    {"op":"join","channel":"#shani"}   {"op":"part","channel":"#shani"}
    {"op":"say","channel":"#shani","text":"hello"}
    {"op":"channels"}                  {"op":"messages","since":42}
    {"op":"quit"}

stdout, one JSON object a line, read by Services/Irc:
    {"event":"status","status":"connecting|connected|error|disconnected","error":"…"}
    {"event":"channels","channels":["#shani"],"nicks":{"#shani":["a","b"]}}
    {"event":"nicks","channel":"#shani","nicks":["a","b"]}
    {"event":"message","message":{seq,channel,nick,text,time,mention}}
    {"event":"messages","messages":[{…}],"since":42}
    {"event":"error","error":"…"}

Only the standard library is used. `make_socket` is injectable so the tests
drive the whole protocol with a fake socket and never touch the network.
"""

from __future__ import annotations

import json
import select
import socket
import ssl
import sys
import time


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _net_connect(host: str, port: int) -> socket.socket:
    return socket.create_connection((host, port), timeout=5)


def _channel(name: str) -> str:
    name = str(name or "").strip()
    if not name:
        return ""
    return name if name.startswith(("#", "&", "+", "!")) else "#" + name


class IrcClient:
    """One connection and its view of the conversation, driven by handle()."""

    def __init__(self, make_socket=None, out=None):
        self.make_socket = make_socket or _net_connect
        self.out = out  # test hook: collects emitted objects
        self.sock = None
        self.buffer = ""
        self.server = ""
        self.nick = ""
        self.status = "disconnected"
        self.error = ""
        self.channels: list[str] = []
        self.nicks: dict[str, list[str]] = {}
        self.messages: list[dict] = []
        self._seq = 0

    # ---- output ----------------------------------------------------------------
    def _emit(self, obj: dict) -> None:
        if self.out is not None:
            self.out(obj)
        else:
            emit(obj)

    def _set_status(self, status: str) -> None:
        self.status = status
        self._emit(
            {
                "event": "status",
                "status": status,
                "error": self.error,
                "server": self.server,
                "nick": self.nick,
            }
        )

    def _emit_channels(self) -> None:
        self._emit(
            {
                "event": "channels",
                "channels": list(self.channels),
                "nicks": {k: list(v) for k, v in self.nicks.items()},
            }
        )

    def send(self, line: str) -> bool:
        if self.sock is None:
            return False
        try:
            self.sock.sendall((line + "\r\n").encode("utf-8"))
            return True
        except OSError as exc:
            self.error = str(exc)
            self._set_status("error")
            self.close()
            return False

    # ---- commands ---------------------------------------------------------------
    def connect(self, server, port=6667, nick="shani", tls=False) -> bool:
        self.close(quiet=True)
        self.server = str(server or "")
        self.nick = str(nick or "shani")
        self.error = ""
        self._set_status("connecting")
        if not self.server:
            self.error = "No server given"
            self._set_status("error")
            return False
        try:
            sock = self.make_socket(self.server, int(port))
            if tls:
                sock = ssl.create_default_context().wrap_socket(
                    sock, server_hostname=self.server
                )
        except Exception as exc:
            self.error = str(exc)
            self._set_status("error")
            return False
        self.sock = sock
        self.send("NICK " + self.nick)
        self.send("USER " + self.nick + " 0 * :" + self.nick)
        return True

    def join(self, channel) -> bool:
        ch = _channel(channel)
        if not ch:
            return False
        if ch not in self.channels:
            self.channels.append(ch)
            self._emit_channels()
        return self.send("JOIN " + ch)

    def part(self, channel) -> bool:
        ch = _channel(channel)
        if not ch:
            return False
        self.channels = [c for c in self.channels if c != ch]
        self.nicks.pop(ch, None)
        self._emit_channels()
        return self.send("PART " + ch)

    def say(self, channel, text) -> bool:
        ch, msg = _channel(channel), str(text or "").strip()
        if not ch or not msg:
            return False
        self._append(ch, self.nick, msg)
        return self.send("PRIVMSG " + ch + " :" + msg)

    def channels_now(self) -> list[str]:
        self._emit_channels()
        return list(self.channels)

    def messages_since(self, since=0) -> list[dict]:
        since = int(since or 0)
        rows = [m for m in self.messages if m["seq"] > since]
        self._emit({"event": "messages", "messages": rows, "since": since})
        return rows

    def quit(self) -> None:
        if self.sock is not None:
            try:
                self.sock.sendall(b"QUIT :bye\r\n")
            except OSError:
                pass
        self.close()
        self._set_status("disconnected")

    def close(self, quiet=False) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.buffer = ""
        if not quiet:
            self.channels = []
            self.nicks = {}
            self._emit_channels()

    # ---- the wire ---------------------------------------------------------------
    def _append(self, channel, nick, text) -> dict:
        self._seq += 1
        mention = (
            bool(self.nick)
            and nick.lower() != self.nick.lower()
            and self.nick.lower() in text.lower()
        )
        msg = {
            "seq": self._seq,
            "channel": channel,
            "nick": nick,
            "text": text,
            "time": time.strftime("%H:%M"),
            "mention": mention,
        }
        self.messages.append(msg)
        self.messages = self.messages[-2000:]
        self._emit({"event": "message", "message": msg})
        return msg

    def feed(self, line: str) -> None:
        """One raw IRC line, without CRLF. Public so tests can drive it."""
        line = line.rstrip("\r\n")
        if not line:
            return
        prefix = ""
        if line.startswith(":"):
            prefix, line = line[1:].split(" ", 1)
        parts = line.split(" ")
        cmd = parts[0].upper()
        args = parts[1:]
        nick = prefix.split("!", 1)[0] if prefix else ""
        if cmd == "PING":
            self.send("PONG :" + (args[0] if args else "").lstrip(":"))
        elif cmd == "001":
            self._set_status("connected")
        elif cmd == "433":
            self.error = "Nickname already in use"
            self._set_status("error")
        elif cmd == "JOIN":
            ch = _channel(args[0] if args else "")
            if ch and ch not in self.channels:
                self.channels.append(ch)
                self._emit_channels()
        elif cmd == "PART":
            ch = _channel(args[0] if args else "")
            self.channels = [c for c in self.channels if c != ch]
            self.nicks.pop(ch, None)
            self._emit_channels()
        elif cmd == "353":
            ch, names = "", []
            for i, a in enumerate(args):
                if a.startswith("#"):
                    ch = _channel(a)
                elif a.startswith(":"):
                    # the names are one space-separated tail, not one token
                    names = " ".join(args[i:]).lstrip(":").split()
                    break
            if ch:
                self.nicks[ch] = names
                self._emit({"event": "nicks", "channel": ch, "nicks": names})
                self._emit_channels()
        elif cmd == "PRIVMSG":
            ch = _channel(args[0] if args else "")
            if ch and len(args) > 1:
                self._append(ch, nick, " ".join(args[1:]).lstrip(":"))

    def read(self) -> None:
        """Read what is waiting on the socket; never block."""
        try:
            data = self.sock.recv(4096)
        except (BlockingIOError, ssl.SSLWantReadError):
            return
        except OSError as exc:
            self.error = str(exc)
            self.close()
            self._set_status("error")
            return
        if not data:
            self.close()
            self._set_status("disconnected")
            return
        self.buffer += data.decode("utf-8", "replace")
        while "\n" in self.buffer:
            line, self.buffer = self.buffer.split("\n", 1)
            self.feed(line)

    # ---- dispatch ---------------------------------------------------------------
    def handle(self, obj: dict) -> None:
        op = str(obj.get("op") or obj.get("cmd") or "").lower()
        if op == "connect":
            self.connect(
                obj.get("server", ""),
                obj.get("port", 6667),
                obj.get("nick", "shani"),
                bool(obj.get("tls")),
            )
        elif op == "join":
            self.join(obj.get("channel", ""))
        elif op == "part":
            self.part(obj.get("channel", ""))
        elif op == "say":
            self.say(obj.get("channel", ""), obj.get("text", ""))
        elif op in ("channels", "channel"):
            self.channels_now()
        elif op in ("messages", "poll"):
            self.messages_since(obj.get("since", 0))
        elif op == "quit":
            self.quit()
        else:
            self._emit({"event": "error", "error": "unknown op: " + op})


def main() -> int:
    client = IrcClient()
    while True:
        watch = [sys.stdin]
        if client.sock is not None:
            watch.append(client.sock)
        try:
            ready, _, _ = select.select(watch, [], [], 0.5)
        except (OSError, ValueError):
            break
        if sys.stdin in ready:
            line = sys.stdin.readline()
            if not line:
                break
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                client.handle(obj)
        if client.sock is not None and client.sock in ready:
            client.read()
    client.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
