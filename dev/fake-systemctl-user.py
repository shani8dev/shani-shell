#!/usr/bin/env python3
"""Stands in for systemctl --user ($FAKE_COMPOSE): user units kept in units.json,
the same state the podman-compose stand-in uses. Calls and failures go to calls and
errors in that dir. Tool from argv[0] or FAKE_SYSTEMCTL_USER_TOOL."""

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


name = canon(
    os.environ.get("FAKE_SYSTEMCTL_USER_TOOL") or os.path.basename(sys.argv[0])
)
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(name + " " + " ".join(a) + "\n")


def save():
    json.dump(st, open(S, "w"))


rc = 0
if not a or a[0] != "--user":
    print("systemctl: only --user is supported", file=sys.stderr)
    rc = 1
else:
    args = a[1:]
    v = args[0] if args else ""
    if v == "daemon-reload":
        pass
    elif v in ("start", "stop", "enable", "disable") and len(args) > 1:
        st[args[-1]] = {"active": v in ("start", "enable")}
        save()
    elif v == "show" and len(args) > 1:
        n = args[-1]
        active = bool((st.get(n) or {}).get("active"))
        print("ActiveState=" + ("active" if active else "inactive"))
        print("SubState=" + ("running" if active else "dead"))
        print("Description=" + (n[:-8] if n.endswith(".service") else n) + " service")
    else:
        print("systemctl: unknown command: %s" % v, file=sys.stderr)
        rc = 1
sys.exit(rc)
