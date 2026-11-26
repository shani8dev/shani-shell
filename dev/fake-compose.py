#!/usr/bin/env python3
"""Stands in for podman-compose ($FAKE_COMPOSE): compose stacks kept in units.json
alongside the user units of the systemctl stand-in. Calls and failures go to calls
and errors in that dir. Tool from argv[0] or FAKE_COMPOSE_TOOL."""

import json, os, sys, traceback

D = os.environ["FAKE_COMPOSE"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
os.makedirs(D, exist_ok=True)
S = os.path.join(D, "units.json")
st = json.load(open(S)) if os.path.exists(S) else {}


def canon(s):
    s = s.lower()
    if s.endswith(".py"):
        s = s[:-3]
    if s.startswith("fake-"):
        s = s[5:]
    return s


name = canon(os.environ.get("FAKE_COMPOSE_TOOL") or os.path.basename(sys.argv[0]))
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(name + " " + " ".join(a) + "\n")


def save():
    json.dump(st, open(S, "w"))


args = []
f = ""
i = 0
while i < len(a):
    if a[i] in ("-f", "--file"):
        f = a[i + 1]
        i += 2
    elif a[i].startswith("--file="):
        f = a[i].split("=", 1)[1]
        i += 1
    elif a[i].startswith("-f") and len(a[i]) > 2:
        f = a[i][2:]
        i += 1
    else:
        args.append(a[i])
        i += 1
rc = 0
v = args[0] if args else ""
if v == "up":
    if f:
        st[f] = {"up": True}
        save()
        open(os.path.join(D, "compose"), "w").write(f + "\n")
    print("Creating compose stack")
    sys.stdout.flush()
    print("Started")
elif v == "down":
    if f:
        st[f] = {"up": False}
        save()
    print("Stopped")
elif v == "logs":
    print("service one: line")
    print("service two: line")
else:
    print("podman-compose: unknown command: %s" % v, file=sys.stderr)
    rc = 1
sys.exit(rc)
