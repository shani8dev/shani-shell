#!/usr/bin/env python3
"""nearby — files to and from devices on the same network, the LocalSend way
(protocol v2: https://github.com/localsend/protocol). LocalSend runs on
Android, iOS, Windows, macOS and Linux, so this reaches all of them, with no
pairing and no account.

Run while the Nearby window is open; one JSON object a line both ways.

stdin (from Services/Nearby):
    {"op": "scan"}                              look for devices
    {"op": "send", "to": FINGERPRINT, "files": [path, …]}
    {"op": "visible", "on": bool}               receive: listen, and announce ourselves
    {"op": "answer", "session": ID, "accept": bool}   a person's answer to an offer
    {"op": "cancel", "session": ID}

stdout (to it):
    {"event": "device", "alias", "fingerprint", "deviceModel", "deviceType", "ip", "port", "protocol"}
    {"event": "offer", "session", "from", "files": [{"name", "size"}]}    asks a person
    {"event": "progress", "session", "done", "total", "direction": "send"|"receive"}
    {"event": "finished", "session", "direction", "files": [path, …]}     received files' paths
    {"event": "failed", "session", "direction", "error"}
    {"event": "visible", "on": bool, "port": n}  {"event": "scanned", "count": n}

Safety, receiving: off until the person turns it on, and then every transfer
is asked (an offer); nothing is written before "accept". A file goes into
~/Downloads/Nearby under its base name only (a "../" or "/" in a name is
dropped, a name taken gets " (2)"), and no larger than it said it would be.
Sending: the device's certificate must hash to the fingerprint it announced,
or nothing is sent. The certificate is our own, made once with openssl
(~/.local/share/shani-shell/nearby).
"""
from __future__ import annotations

import hashlib
import http.client
import ipaddress
import json
import os
import re
import secrets
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

GROUP = "224.0.0.167"
PORT = int(os.environ.get("SHANI_NEARBY_PORT", "53317"))
API = "/api/localsend/v2"
DATA = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "shani-shell" / "nearby"
# where received files go: ~/Downloads/Nearby (SHANI_NEARBY_DIR for the tests)
INBOX = Path(os.environ.get("SHANI_NEARBY_DIR") or (Path(os.environ.get("XDG_DOWNLOAD_DIR") or Path.home() / "Downloads") / "Nearby"))
# where to look besides multicast: "ip:port,…" (the tests; a device on another subnet)
EXTRA = [x for x in os.environ.get("SHANI_NEARBY_PEERS", "").split(",") if x]
OFFER_TIMEOUT = float(os.environ.get("SHANI_NEARBY_OFFER_TIMEOUT", "60"))

out_lock = threading.Lock()


def emit(obj: dict) -> None:
    with out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


# ---- who we are ----------------------------------------------------------------------
def certificate() -> tuple[Path, Path, str]:
    DATA.mkdir(parents=True, exist_ok=True)
    cert, key = DATA / "cert.pem", DATA / "key.pem"
    if not (cert.exists() and key.exists()):
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650", "-subj", "/CN=LocalSend User",
                        "-keyout", str(key), "-out", str(cert)], check=True, capture_output=True)
        os.chmod(key, 0o600)
    der = ssl.PEM_cert_to_DER_cert(cert.read_text())
    return cert, key, hashlib.sha256(der).hexdigest().upper()


def alias() -> str:
    name = os.environ.get("SHANI_NEARBY_ALIAS")
    if name:
        return name
    try:
        full = (Path("/etc/passwd").read_text().split("\n"))
        user = os.environ.get("USER", "")
        for line in full:
            parts = line.split(":")
            if parts[0] == user and len(parts) > 4 and parts[4].split(",")[0]:
                return parts[4].split(",")[0] + "'s " + socket.gethostname()
    except OSError:
        pass
    return socket.gethostname()


class Me:
    def __init__(self):
        self.cert, self.key, self.fingerprint = certificate()
        self.alias = alias()

    def info(self, announce: bool | None = None) -> dict:
        d = {"alias": self.alias, "version": "2.1", "deviceModel": "ShaniOS", "deviceType": "desktop",
             "fingerprint": self.fingerprint, "port": PORT, "protocol": "https", "download": False}
        if announce is not None:
            d["announce"] = announce
        return d


# ---- talking to a device ----------------------------------------------------------------
def client_context() -> ssl.SSLContext:
    # LocalSend's certificates are self-signed: who a device is, is its fingerprint,
    # checked by hand on every connection (pinned) instead of by a certificate authority
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def request(ip: str, port: int, method: str, path: str, body: bytes | None = None, fingerprint: str = "",
            timeout: float = 5.0, protocol: str = "https") -> tuple[int, bytes]:
    if protocol == "https":
        conn = http.client.HTTPSConnection(ip, port, timeout=timeout, context=client_context())
    else:
        conn = http.client.HTTPConnection(ip, port, timeout=timeout)
    try:
        conn.connect()
        if protocol == "https" and fingerprint:
            der = conn.sock.getpeercert(binary_form=True)
            if hashlib.sha256(der).hexdigest().upper() != fingerprint.upper():
                raise ConnectionError("that device's certificate is not the one it announced")
        conn.request(method, path, body=body, headers={"Content-Type": "application/json" if body and body[:1] in (b"{", b"[") else "application/octet-stream"})
        r = conn.getresponse()
        return r.status, r.read()
    finally:
        conn.close()


class Devices:
    def __init__(self, me: Me):
        self.me = me
        self.known: dict[str, dict] = {}

    def saw(self, info: dict, ip: str) -> None:
        fp = str(info.get("fingerprint", ""))
        if not fp or fp == self.me.fingerprint:
            return
        dev = {"alias": str(info.get("alias", ""))[:80], "fingerprint": fp, "deviceModel": str(info.get("deviceModel") or "")[:60],
               "deviceType": str(info.get("deviceType") or "")[:20], "ip": ip, "port": int(info.get("port") or PORT),
               "protocol": "http" if info.get("protocol") == "http" else "https"}
        if self.known.get(fp) != dev:
            self.known[fp] = dev
            emit(dict(dev, event="device"))

    # ask one address who it is (LocalSend's register, unicast): works with the
    # firewall closed, since it is we who connect
    def ask(self, ip: str, port: int) -> None:
        for proto in ("https", "http"):
            try:
                status, body = request(ip, port, "POST", API + "/register", json.dumps(self.me.info()).encode(), timeout=1.2, protocol=proto)
            except (OSError, ConnectionError, ssl.SSLError, http.client.HTTPException):
                continue
            if status == 200:
                try:
                    info = json.loads(body)
                except json.JSONDecodeError:
                    return
                info.setdefault("protocol", proto)
                info.setdefault("port", port)
                self.saw(info, ip)
                return

    def scan(self) -> None:
        targets = [(h.rsplit(":", 1)[0], int(h.rsplit(":", 1)[1])) for h in EXTRA]
        # SHANI_NEARBY_SUBNET=0: only the named peers (the tests; no sweep of a real network)
        for net in (local_networks() if os.environ.get("SHANI_NEARBY_SUBNET", "1") != "0" else []):
            targets += [(str(h), PORT) for h in net.hosts()][:254]
        announce(self.me)
        before = len(self.known)
        with ThreadPoolExecutor(max_workers=64) as pool:
            list(pool.map(lambda t: self.ask(*t), targets))
        emit({"event": "scanned", "count": len(self.known), "new": len(self.known) - before})


def local_networks() -> list:
    """The /24 around each address this computer has on a LAN (not loopback,
    not containers' bridges); the subnet scan stays small and local."""
    nets = []
    try:
        out = subprocess.run(["ip", "-j", "-4", "addr"], capture_output=True, text=True).stdout
        for link in json.loads(out or "[]"):
            name = link.get("ifname", "")
            if name == "lo" or name.startswith(("docker", "br-", "veth", "virbr", "podman", "lxc")):
                continue
            for a in link.get("addr_info", []):
                ip = ipaddress.ip_interface(f"{a['local']}/{max(24, a.get('prefixlen', 24))}")
                if ip.ip.is_private:
                    nets.append(ip.network)
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    return nets


def announce(me: Me) -> None:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
        s.sendto(json.dumps(me.info(announce=True)).encode(), (GROUP, PORT))
        s.close()
    except OSError:
        pass


def listen_multicast(devices: Devices, stop: threading.Event) -> None:
    """Announcements from others (reaches us only while the port is open)."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("", PORT))
        s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, struct.pack("4sl", socket.inet_aton(GROUP), socket.INADDR_ANY))
        s.settimeout(1.0)
    except OSError:
        return
    while not stop.is_set():
        try:
            data, (ip, _port) = s.recvfrom(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            info = json.loads(data)
        except json.JSONDecodeError:
            continue
        devices.saw(info, ip)
        if info.get("announce") and info.get("fingerprint") != devices.me.fingerprint:
            threading.Thread(target=devices.ask, args=(ip, int(info.get("port") or PORT)), daemon=True).start()
    s.close()


# ---- sending ----------------------------------------------------------------------------------
def send(me: Me, dev: dict, paths: list[str]) -> None:
    session = "out-" + secrets.token_hex(4)
    files, ids = {}, {}
    for p in paths:
        path = Path(p)
        if not path.is_file():
            emit({"event": "failed", "session": session, "direction": "send", "error": f"not a file: {path.name}"})
            return
        fid = secrets.token_hex(6)
        ids[fid] = path
        files[fid] = {"id": fid, "fileName": path.name, "size": path.stat().st_size, "fileType": "application/octet-stream"}
    total = sum(f["size"] for f in files.values())
    emit({"event": "progress", "session": session, "done": 0, "total": total, "direction": "send", "to": dev["alias"], "waiting": True})
    try:
        status, body = request(dev["ip"], dev["port"], "POST", API + "/prepare-upload", json.dumps({"info": me.info(), "files": files}).encode(),
                               fingerprint=dev["fingerprint"], timeout=OFFER_TIMEOUT + 5, protocol=dev["protocol"])
        if status == 204:
            emit({"event": "finished", "session": session, "direction": "send", "files": paths})
            return
        if status != 200:
            why = {403: "they declined", 401: "it asks for a PIN", 409: "it is busy with another transfer", 429: "too many requests"}.get(status, f"refused ({status})")
            emit({"event": "failed", "session": session, "direction": "send", "error": why})
            return
        prep = json.loads(body)
        sid, tokens = prep["sessionId"], prep.get("files", {})
        done = 0
        for fid, path in ids.items():
            if fid not in tokens:
                continue              # the device left that file out
            q = f"sessionId={sid}&fileId={fid}&token={tokens[fid]}"
            status, _ = request(dev["ip"], dev["port"], "POST", API + "/upload?" + q, path.read_bytes(),
                                fingerprint=dev["fingerprint"], timeout=120, protocol=dev["protocol"])
            if status != 200:
                emit({"event": "failed", "session": session, "direction": "send", "error": f"{path.name} was refused ({status})"})
                return
            done += files[fid]["size"]
            emit({"event": "progress", "session": session, "done": done, "total": total, "direction": "send", "to": dev["alias"]})
        emit({"event": "finished", "session": session, "direction": "send", "files": paths})
    except (OSError, ConnectionError, ssl.SSLError, http.client.HTTPException, json.JSONDecodeError, KeyError) as exc:
        emit({"event": "failed", "session": session, "direction": "send", "error": str(exc) or exc.__class__.__name__})


# ---- receiving ------------------------------------------------------------------------------
def safe_name(name: str) -> str:
    base = re.sub(r"[\x00-\x1f/\\]", "_", Path(str(name).replace("\\", "/")).name).strip(" .")
    return base[:200] or "file"


def unique(folder: Path, name: str) -> Path:
    target = folder / name
    stem, dot, ext = name.partition(".") if not name.startswith(".") else (name, "", "")
    n = 2
    while target.exists():
        target = folder / (f"{stem} ({n}){dot}{ext}")
        n += 1
    return target


class Receiver:
    def __init__(self, me: Me, devices: Devices):
        self.me, self.devices = me, devices
        self.server: ThreadingHTTPServer | None = None
        self.sessions: dict[str, dict] = {}
        self.answers: dict[str, threading.Event] = {}
        self.accepted: dict[str, bool] = {}
        self.stop = threading.Event()

    def start(self) -> bool:
        if self.server:
            return True
        receiver = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def reply(self, code: int, obj=None):
                data = json.dumps(obj).encode() if obj is not None else b""
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def body(self, limit: int) -> bytes:
                n = int(self.headers.get("Content-Length") or 0)
                if n > limit:
                    raise ValueError("too large")
                return self.rfile.read(n)

            def do_GET(self):
                if urlparse(self.path).path == API + "/info":
                    return self.reply(200, receiver.me.info())
                self.reply(404)

            def do_POST(self):
                u = urlparse(self.path)
                q = {k: v[0] for k, v in parse_qs(u.query).items()}
                try:
                    if u.path == API + "/register":
                        info = json.loads(self.body(64 * 1024) or b"{}")
                        receiver.devices.saw(info, self.client_address[0])
                        return self.reply(200, receiver.me.info())
                    if u.path == API + "/prepare-upload":
                        return receiver.prepare(self, json.loads(self.body(1024 * 1024)))
                    if u.path == API + "/upload":
                        return receiver.upload(self, q)
                    if u.path == API + "/cancel":
                        receiver.sessions.pop(q.get("sessionId", ""), None)
                        return self.reply(200)
                except (ValueError, json.JSONDecodeError):
                    return self.reply(400, {"message": "bad request"})
                self.reply(404)

        try:
            srv = ThreadingHTTPServer(("", PORT), Handler)
        except OSError as exc:
            emit({"event": "failed", "session": "", "direction": "receive", "error": f"port {PORT}: {exc.strerror}"})
            return False
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(str(self.me.cert), str(self.me.key))
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
        srv.daemon_threads = True
        self.server = srv
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.stop.clear()
        threading.Thread(target=listen_multicast, args=(self.devices, self.stop), daemon=True).start()
        announce(self.me)
        return True

    def close(self) -> None:
        if self.server:
            self.server.shutdown()
            self.server.server_close()
            self.server = None
        self.stop.set()
        for ev in self.answers.values():
            ev.set()

    def prepare(self, h, req: dict) -> None:
        if any(s.get("active") for s in self.sessions.values()):
            return h.reply(409, {"message": "busy"})
        info = req.get("info") or {}
        files = req.get("files") or {}
        if not isinstance(files, dict) or not files or len(files) > 1000:
            return h.reply(400, {"message": "no files"})
        sid = secrets.token_hex(8)
        listed = [{"id": str(fid), "name": safe_name(f.get("fileName", "")), "size": int(f.get("size") or 0)} for fid, f in files.items()]
        ev = threading.Event()
        self.answers[sid] = ev
        emit({"event": "offer", "session": sid, "from": str(info.get("alias", h.client_address[0]))[:80],
              "files": [{"name": f["name"], "size": f["size"]} for f in listed]})
        # the person answers in the window (or the notification); no answer is a no
        ev.wait(OFFER_TIMEOUT)
        if not self.accepted.pop(sid, False) or not self.server:
            self.answers.pop(sid, None)
            emit({"event": "failed", "session": sid, "direction": "receive", "error": "declined"})
            return h.reply(403, {"message": "declined"})
        tokens = {f["id"]: secrets.token_hex(8) for f in listed}
        self.sessions[sid] = {"active": True, "files": {f["id"]: dict(f, token=tokens[f["id"]]) for f in listed}, "saved": [],
                              "total": sum(f["size"] for f in listed), "done": 0}
        h.reply(200, {"sessionId": sid, "files": tokens})

    def upload(self, h, q: dict) -> None:
        s = self.sessions.get(q.get("sessionId", ""))
        f = s and s["files"].get(q.get("fileId", ""))
        if not f or q.get("token") != f["token"] or f.get("written"):
            return h.reply(403, {"message": "no such transfer"})
        n = int(h.headers.get("Content-Length") or 0)
        if n > f["size"]:
            return h.reply(400, {"message": "larger than offered"})
        INBOX.mkdir(parents=True, exist_ok=True)
        target = unique(INBOX, f["name"])
        part = target.with_name(target.name + ".part")
        left = n
        with open(part, "wb") as out:
            while left > 0:
                chunk = h.rfile.read(min(1 << 20, left))
                if not chunk:
                    break
                out.write(chunk)
                left -= len(chunk)
                s["done"] += len(chunk)
                emit({"event": "progress", "session": q["sessionId"], "done": s["done"], "total": s["total"], "direction": "receive"})
        if left:
            part.unlink(missing_ok=True)
            return h.reply(400, {"message": "cut short"})
        part.rename(target)
        f["written"] = True
        s["saved"].append(str(target))
        h.reply(200)
        if all(x.get("written") for x in s["files"].values()):
            s["active"] = False
            emit({"event": "finished", "session": q["sessionId"], "direction": "receive", "files": s["saved"]})

    def answer(self, sid: str, accept: bool) -> None:
        self.accepted[sid] = bool(accept)
        ev = self.answers.get(sid)
        if ev:
            ev.set()


def main() -> int:
    me = Me()
    devices = Devices(me)
    receiver = Receiver(me, devices)
    emit({"event": "ready", "alias": me.alias, "fingerprint": me.fingerprint, "port": PORT})
    for line in sys.stdin:
        try:
            cmd = json.loads(line)
        except json.JSONDecodeError:
            continue
        op = cmd.get("op")
        if op == "scan":
            threading.Thread(target=devices.scan, daemon=True).start()
        elif op == "send":
            dev = devices.known.get(cmd.get("to", ""))
            if not dev:
                emit({"event": "failed", "session": "", "direction": "send", "error": "that device is not here any more"})
            else:
                threading.Thread(target=send, args=(me, dev, list(cmd.get("files") or [])), daemon=True).start()
        elif op == "visible":
            on = bool(cmd.get("on")) and receiver.start()
            if not cmd.get("on"):
                receiver.close()
            emit({"event": "visible", "on": on, "port": PORT})
        elif op == "answer":
            receiver.answer(str(cmd.get("session", "")), bool(cmd.get("accept")))
        elif op == "cancel":
            receiver.answer(str(cmd.get("session", "")), False)
    receiver.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
