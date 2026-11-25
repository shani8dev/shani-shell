#!/usr/bin/env python3
"""What starts at login: XDG autostart, the system's and the person's.

The one implementation behind Settings > Default apps > Startup apps (it was
two: the Startup manager window's Python and the Settings page's shell + sed).
A system entry turned off gets a Hidden=true copy in the user's folder - the
XDG way to override one you cannot edit - and turns back on without it.

  autostart.py list                     {"entries": [{file, name, desc, on, mine}]}
  autostart.py set '{"file": F, "on": B}'
  autostart.py add '{"id": APP_ID}'     the app's own desktop file, from XDG data dirs
  autostart.py add '{"path": FILE}'     any .desktop file
  autostart.py remove FILE              the user's own entry

Every answer is one JSON object; a failure is {"error": "..."} with exit 0, so
the caller can show it. Names are checked: a file argument is a bare
*.desktop name, never a path.
"""
import json
import os
import shutil
import sys

SYSTEM = "/etc/xdg/autostart"


def user_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "autostart")


def fields(path):
    d = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("[") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                d.setdefault(k.strip().lower(), v.strip())   # the first (unlocalised) value wins
    except OSError:
        pass
    return d


def safe(name):
    return name.endswith(".desktop") and name != ".desktop" and "/" not in name and ".." not in name


def emit(obj):
    print(json.dumps(obj, default=str))
    return 0


def cmd_list(user):
    found = {}
    for folder, mine in ((user, True), (SYSTEM, False)):
        try:
            names = sorted(n for n in os.listdir(folder) if n.endswith(".desktop"))
        except OSError:
            names = []
        for n in names:
            if n in found:
                continue                   # the user's copy wins over the system's
            d = fields(os.path.join(folder, n))
            if not d.get("name") and not d.get("exec"):
                continue
            hidden = d.get("hidden", "false").lower() == "true" \
                or d.get("x-gnome-autostart-enabled", "true").lower() == "false"
            found[n] = {"file": n, "name": d.get("name") or n[:-8], "desc": d.get("comment") or "",
                        "on": not hidden, "mine": mine}
    return emit({"entries": sorted(found.values(), key=lambda e: e["name"].lower())})


def cmd_set(user, arg):
    o = json.loads(arg or "{}")
    f = o.get("file", "")
    if not safe(f):
        return emit({"error": "Invalid desktop file"})
    p = os.path.join(user, f)
    if not os.path.isfile(p):
        s = os.path.join(SYSTEM, f)
        if not os.path.isfile(s):
            return emit({"error": "Not found"})
        os.makedirs(user, exist_ok=True)
        shutil.copyfile(s, p)
    with open(p, encoding="utf-8", errors="replace") as fh:
        lines = [l for l in fh if not l.strip().lower().startswith(("hidden=", "x-gnome-autostart-enabled="))]
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    if not o.get("on"):
        lines.append("Hidden=true\n")
    with open(p, "w", encoding="utf-8") as fh:
        fh.writelines(lines)
    return emit({"ok": True})


def cmd_add(user, arg):
    o = json.loads(arg or "{}")
    ident, path = o.get("id", ""), o.get("path", "")
    if ident:
        if not all(c.isalnum() or c in "._-" for c in ident):
            return emit({"error": "Invalid app id"})
        base = ident + ".desktop"
        dirs = [os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")] \
            + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
        src = next((c for c in (os.path.join(d, "applications", base) for d in dirs) if os.path.isfile(c)), "")
        if not src:
            return emit({"error": "Desktop file not found"})
    elif path:
        if not path.endswith(".desktop") or not os.path.isfile(path):
            return emit({"error": "Choose a .desktop file"})
        base, src = os.path.basename(path), path
    else:
        return emit({"error": "Pick an app first"})
    if not safe(base):
        return emit({"error": "Invalid desktop file"})
    os.makedirs(user, exist_ok=True)
    shutil.copyfile(src, os.path.join(user, base))
    return emit({"ok": True, "file": base})


def cmd_remove(user, arg):
    if not safe(arg or ""):
        return emit({"error": "Invalid desktop file"})
    p = os.path.join(user, arg)
    if os.path.isfile(p):
        os.remove(p)
    return emit({"ok": True})


def main(argv):
    mode = argv[1] if len(argv) > 1 else "list"
    arg = argv[2] if len(argv) > 2 else ""
    user = user_dir()
    try:
        if mode == "list":
            return cmd_list(user)
        if mode == "set":
            return cmd_set(user, arg)
        if mode == "add":
            return cmd_add(user, arg)
        if mode == "remove":
            return cmd_remove(user, arg)
        return emit({"error": "Unknown action"})
    except (OSError, ValueError) as e:
        return emit({"error": f"Could not change the autostart folder: {e.__class__.__name__}"})


if __name__ == "__main__":
    sys.exit(main(sys.argv))
