#!/usr/bin/env python3
"""modules — loaded kernel modules from /proc/modules and /sys/module.

    modules.py list     JSON: {"modules":[{"name","size","used","usedBy","state"}], "count":N}
    modules.py params --name NAME   JSON: {"name","params":[{"name","value"}]}

Read-only. /proc/modules is space-separated (not tabs). No tool, no root.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


def _modules():
    mods = []
    try:
        with open("/proc/modules", encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 6:
                    continue
                name, size, used, used_by, state = parts[0], parts[1], parts[2], parts[3], parts[4]
                deps = [] if used_by == "-" else [d for d in used_by.split(",") if d]
                mods.append({
                    "name": name,
                    "size": int(size) if size.isdigit() else 0,
                    "used": int(used) if used.isdigit() else 0,
                    "usedBy": deps,
                    "state": state.rstrip(","),
                })
    except OSError:
        pass
    mods.sort(key=lambda m: m["name"])
    return mods


def cmd_list(_a):
    mods = _modules()
    return {"modules": mods, "count": len(mods)}


def cmd_params(a):
    name = a.name or ""
    if not NAME_RE.match(name):
        return {"name": name, "params": [], "error": "bad name"}
    base = f"/sys/module/{name}/parameters"
    params = []
    try:
        for p in sorted(os.listdir(base)):
            pp = os.path.join(base, p)
            try:
                with open(pp, encoding="utf-8", errors="replace") as f:
                    val = f.read().strip()
            except OSError:
                val = "(unreadable)"
            params.append({"name": p, "value": val})
    except OSError:
        pass
    return {"name": name, "params": params}


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    p = sub.add_parser("params"); p.add_argument("--name", required=True)
    args = ap.parse_args()
    fn = {"list": cmd_list, "params": cmd_params}[args.cmd]
    json.dump(fn(args), sys.stdout)
    print()


if __name__ == "__main__":
    main()
