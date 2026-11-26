#!/usr/bin/env python3
"""Stands in for waydroid and waydroid-helper ($FAKE_WAYDROID): status and session
kept in status.json, a notinitialised marker for a fresh install. Calls and
failures go to calls and errors in that dir. Tool from argv[0] or FAKE_WAYDROID_TOOL."""

import json, os, sys, traceback

D = os.environ["FAKE_WAYDROID"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
os.makedirs(D, exist_ok=True)
S = os.path.join(D, "status.json")
M = os.path.join(D, "notinitialised")


def blank():
    return {"initialised": True, "session": "STOPPED"}


st = json.load(open(S)) if os.path.exists(S) else blank()
for k, val in blank().items():
    st.setdefault(k, val)


def canon(s):
    s = s.lower()
    if s.endswith(".py"):
        s = s[:-3]
    if s.startswith("fake-"):
        s = s[5:]
    return s


name = canon(os.environ.get("FAKE_WAYDROID_TOOL") or os.path.basename(sys.argv[0]))
tool = "waydroid-helper" if "helper" in name else "waydroid"
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(tool + " " + " ".join(a) + "\n")


def save():
    json.dump(st, open(S, "w"))


rc = 0
v = a[0] if a else ""
if tool == "waydroid-helper":
    if v == "init":
        print("Initialising Waydroid")
        sys.stdout.flush()
        if os.path.exists(M):
            os.remove(M)
        st["initialised"] = True
        save()
        print("Android image installed")
        sys.stdout.flush()
    else:
        print("waydroid-helper: unknown command: %s" % v, file=sys.stderr)
        rc = 1
elif v == "status":
    if os.path.exists(M):
        print("Status: STOPPED")
        print("Waydroid is not initialized")
    else:
        print("Status: " + st["session"])
        print("Vendor type: WAYDROID")
        print("Session: " + st["session"])
elif v == "session" and len(a) > 1:
    if a[1] in ("start", "stop"):
        st["session"] = "RUNNING" if a[1] == "start" else "STOPPED"
        save()
        print("Session started" if a[1] == "start" else "Session stopped")
    else:
        print("waydroid: unknown session command: %s" % a[1], file=sys.stderr)
        rc = 1
elif v == "show-full-ui":
    pass  # the UI window changes nothing here
else:
    print("waydroid: unknown command: %s" % v, file=sys.stderr)
    rc = 1
sys.exit(rc)
