#!/usr/bin/env python3
"""cloud — cloud drives in Files (rclone, which the system has): added once with
the provider's own sign-in in the browser, then mounted like any drive.

    cloud.py list                     [{"name", "type", "label", "path", "mounted"}]
    cloud.py add <name> <type>        a new one; the sign-in page opens in the
                                      browser (Google Drive, OneDrive, Dropbox, Box,
                                      pCloud, Yandex). Nextcloud / WebDAV: its
                                      {"url", "user", "password"} on stdin instead
    cloud.py mount <name>             {"path"}: $XDG_RUNTIME_DIR/cloud/<name>
    cloud.py remove <name>            unmounted and forgotten (rclone's sign-in
                                      deleted; nothing in the cloud is touched)

A mounted drive is a FUSE mount, so Files lists it under Devices and closes it
with fusermount3 like sshfs. Files that are changed are written through a local
cache (--vfs-cache-mode writes), so any app can save into them. The sign-ins
stay in rclone's own config (~/.config/rclone/rclone.conf), as rclone keeps them.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

TYPES = {"drive": "Google Drive", "onedrive": "OneDrive", "dropbox": "Dropbox", "box": "Box",
         "pcloud": "pCloud", "yandex": "Yandex Disk", "webdav": "Nextcloud / WebDAV"}


def _rclone(*args, **kw):
    return subprocess.run([shutil.which("rclone") or "rclone", *args], capture_output=True, text=True, **kw)


def point(name: str) -> str:
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "cloud", name)


def _mounted(p: str) -> bool:
    try:
        with open("/proc/self/mountinfo", encoding="utf-8", errors="replace") as f:
            return any(line.split()[4] == p for line in f)
    except OSError:
        return False


def remotes() -> list[dict]:
    r = _rclone("listremotes", "--long")
    out = []
    for line in r.stdout.splitlines():
        m = re.match(r"^(.+?):\s+(\S+)\s*$", line)
        if not m:
            continue
        name, kind = m.groups()
        p = point(name)
        out.append({"name": name, "type": kind, "label": TYPES.get(kind, kind), "path": p, "mounted": _mounted(p)})
    return out


def add(name: str, kind: str, answers: dict) -> dict:
    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9 _-]{0,40}$", name or ""):
        return {"error": "a name of letters, digits, spaces, - and _"}
    if kind not in TYPES:
        return {"error": "not a cloud this knows: %s" % kind}
    if any(x["name"] == name for x in remotes()):
        return {"error": "%s is there already" % name}
    if kind == "webdav":
        url, user, pw = answers.get("url", ""), answers.get("user", ""), answers.get("password", "")
        if not url.startswith(("https://", "http://")):
            return {"error": "the address starts with https://"}
        ob = _rclone("obscure", "-", input=pw).stdout.strip() if pw else ""     # never the password itself on a command line
        args = ["config", "create", name, "webdav", "url=" + url, "vendor=" + ("nextcloud" if "nextcloud" in url or "/remote.php/" in url else "other"),
                "user=" + user] + (["pass=" + ob] if ob else [])
        r = _rclone(*args, timeout=60)
    else:
        # rclone opens the provider's sign-in in the browser and waits for its answer
        # on 127.0.0.1:53682; a person has a few minutes to sign in
        r = _rclone("config", "create", name, kind, "config_is_local=true", timeout=600)
    if r.returncode != 0:
        _rclone("config", "delete", name)
        return {"error": (r.stderr.strip().splitlines() or ["the sign-in did not finish"])[-1]}
    return {"ok": True, "name": name}


def mount(name: str) -> dict:
    if not any(x["name"] == name for x in remotes()):
        return {"error": "no cloud drive called %s" % name}
    p = point(name)
    if _mounted(p):
        return {"path": p}
    os.makedirs(p, exist_ok=True)
    r = _rclone("mount", name + ":", p, "--vfs-cache-mode", "writes", "--daemon", "--daemon-wait", "30s", timeout=60)
    if r.returncode != 0:
        try:
            os.rmdir(p)
        except OSError:
            pass
        return {"error": (r.stderr.strip().splitlines() or ["it could not be opened"])[-1]}
    return {"path": p}


def remove(name: str) -> dict:
    p = point(name)
    if _mounted(p):
        subprocess.run([shutil.which("fusermount3") or "fusermount3", "-u", p], capture_output=True)
    try:
        os.rmdir(p)
    except OSError:
        pass
    r = _rclone("config", "delete", name)
    return {"ok": r.returncode == 0} if r.returncode == 0 else {"error": r.stderr.strip() or "it could not be removed"}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if not shutil.which("rclone"):
        print(json.dumps({"error": "rclone is not installed"}))
        return 3
    try:
        if cmd == "list" and not args:
            print(json.dumps(remotes()))
            return 0
        if cmd == "add" and len(args) == 2:
            answers = {}
            if args[1] == "webdav":
                try:
                    answers = json.loads(sys.stdin.readline() or "{}")
                except ValueError:
                    pass
            r = add(args[0], args[1], answers if isinstance(answers, dict) else {})
        elif cmd == "mount" and len(args) == 1:
            r = mount(args[0])
        elif cmd == "remove" and len(args) == 1:
            r = remove(args[0])
        else:
            r = None
    except subprocess.TimeoutExpired:
        r = {"error": "it took too long (the sign-in was not finished)"}
    if r is not None:
        print(json.dumps(r))
        return 1 if "error" in r else 0
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
