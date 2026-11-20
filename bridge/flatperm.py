#!/usr/bin/env python3
"""flatperm — a Flatpak app's permissions, as Flatseal shows them, and changes to
them; through the `flatpak` command, as `flatpak override --user` (what the app
asked for stays; the change is yours, and Reset takes it back).

    flatperm.py apps                      [{"id", "name"}]
    flatperm.py show <app>                {"shared", "sockets", "devices", "features",
                                           "filesystems", "persistent", "env",
                                           "session", "system", "changed", "portals"}
    flatperm.py set <app> <flag>...       flatpak override --user <flag>... <app>,
                                          then show; a flag is one of override's
                                          own (--socket=x11, --nofilesystem=home ...)
    flatperm.py portal <app> <table> <id> yes|no|reset
                                          a portal's answer for it: notifications,
                                          background, camera, location ...
    flatperm.py reset <app>               every change of yours taken back

"changed": what your overrides touch, so the page can mark it. "portals": the
permission store's answers for it ({"notifications": "yes", ...}).
SHANI_FLATPAK (tests): the flatpak to run.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys

FLATPAK = shlex.split(os.environ.get("SHANI_FLATPAK", "flatpak"))
LISTS = {"shared": "shared", "sockets": "sockets", "devices": "devices", "features": "features",
         "filesystems": "filesystems", "persistent": "persistent"}
# the portals Flatseal shows, as the permission store files them: name -> (table, id)
PORTALS = {"notifications": ("notifications", "notification"), "background": ("background", "background"),
           "camera": ("devices", "camera"), "location": ("location", "location"),
           "screenshot": ("screenshot", "screenshot")}
# what may be passed to `flatpak override`: its own flags, nothing else
FLAG = re.compile(r"^--(no)?(share|unshare|socket|nosocket|device|nodevice|allow|disallow|filesystem|nofilesystem|persist|"
                  r"env|unset-env|talk-name|no-talk-name|own-name|system-talk-name|system-no-talk-name|system-own-name)(=\S.*)?$")


def _run(*args, check=False):
    return subprocess.run(FLATPAK + list(args), capture_output=True, text=True, timeout=60)


def parse_keyfile(text: str) -> dict:
    """The [Context] / [Session Bus Policy] / [System Bus Policy] / [Environment]
    sections flatpak prints, as {section: {key: value}}."""
    out, sec = {}, None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            sec = out.setdefault(m.group(1), {})
            continue
        if sec is not None and "=" in line:
            k, v = line.split("=", 1)
            sec[k.strip()] = v.strip()
    return out


def as_perms(kf: dict) -> dict:
    ctx = kf.get("Context", {})
    p = {name: [x for x in ctx.get(key, "").split(";") if x] for name, key in LISTS.items()}
    p["env"] = dict(kf.get("Environment", {}))
    p["session"] = dict(kf.get("Session Bus Policy", {}))
    p["system"] = dict(kf.get("System Bus Policy", {}))
    return p


def parse_portals(text: str) -> dict:
    """`flatpak permission-show APP`: Table Object App Permissions [Data] rows."""
    out = {}
    for line in text.splitlines()[1:]:
        cols = line.split()
        if len(cols) < 4:
            continue
        table, obj, perm = cols[0], cols[1], cols[3].strip(",")
        for name, (t, i) in PORTALS.items():
            if t == table and i == obj:
                out[name] = perm
    return out


def apps() -> list[dict]:
    r = _run("list", "--app", "--columns=application,name")
    out = []
    for line in r.stdout.splitlines():
        if "\t" in line:
            i, n = line.split("\t", 1)
            out.append({"id": i.strip(), "name": n.strip() or i.strip()})
    return sorted(out, key=lambda a: a["name"].lower())


def show(app: str) -> dict:
    eff = as_perms(parse_keyfile(_run("info", "--show-permissions", app).stdout))
    mine = as_perms(parse_keyfile(_run("override", "--user", "--show", app).stdout))
    # a name in an override list means you changed it ("!x" there means turned off)
    changed = {k: sorted({x.lstrip("!") for x in v}) for k, v in mine.items() if isinstance(v, list) and v}
    for k in ("env", "session", "system"):
        if mine[k]:
            changed[k] = sorted(mine[k])
    eff["changed"] = changed
    eff["portals"] = parse_portals(_run("permission-show", app).stdout)
    return eff


def set_flags(app: str, flags: list[str]) -> dict:
    bad = [f for f in flags if not FLAG.match(f)]
    if bad:
        return {"error": "not a permission: %s" % bad[0]}
    r = _run("override", "--user", *flags, app)
    if r.returncode != 0:
        return {"error": (r.stderr.strip().splitlines() or ["flatpak override failed"])[-1]}
    return show(app)


def portal(app: str, name: str, value: str) -> dict:
    if name not in PORTALS or value not in ("yes", "no", "reset"):
        return {"error": "not a portal answer: %s %s" % (name, value)}
    table, obj = PORTALS[name]
    r = _run("permission-remove", table, obj, app) if value == "reset" else _run("permission-set", table, obj, app, value)
    if r.returncode != 0:
        return {"error": (r.stderr.strip().splitlines() or ["flatpak permission failed"])[-1]}
    return show(app)


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    try:
        if cmd == "apps":
            r = apps()
        elif cmd == "show" and len(args) == 1:
            r = show(args[0])
        elif cmd == "set" and len(args) >= 2:
            r = set_flags(args[0], args[1:])
        elif cmd == "portal" and len(args) == 3:
            r = portal(*args)
        elif cmd == "reset" and len(args) == 1:
            res = _run("override", "--user", "--reset", args[0])
            r = show(args[0]) if res.returncode == 0 else {"error": res.stderr.strip() or "reset failed"}
        else:
            print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
            return 2
    except (OSError, subprocess.TimeoutExpired) as e:
        r = {"error": str(e)}
    print(json.dumps(r))
    return 1 if isinstance(r, dict) and "error" in r else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
