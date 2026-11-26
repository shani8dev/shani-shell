#!/usr/bin/env python3
"""Stands in for lxc and lxd ($FAKE_LXC): instances kept in instances.json,
answered in lxc's own JSON shape. Calls and failures go to $FAKE_LXC/calls and
/errors. The tool comes from the name it is run as, or FAKE_LXC_TOOL."""

import json, os, sys, traceback

D = os.environ["FAKE_LXC"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
os.makedirs(D, exist_ok=True)
S = os.path.join(D, "instances.json")


def blank():
    return {
        "instances": [
            {
                "name": "web-lxd",
                "status": "RUNNING",
                "image": "ubuntu:24.04",
                "type": "container",
                "address": "10.0.0.12",
            }
        ]
    }


st = json.load(open(S)) if os.path.exists(S) else blank()
st.setdefault("instances", blank()["instances"])


def canon(s):
    s = s.lower()
    if s.endswith(".py"):
        s = s[:-3]
    if s.startswith("fake-"):
        s = s[5:]
    return s


name = canon(os.environ.get("FAKE_LXC_TOOL") or os.path.basename(sys.argv[0]))
tool = "lxd" if "lxd" in name else "lxc"
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(tool + " " + " ".join(a) + "\n")


def save():
    json.dump(st, open(S, "w"))


def find(n):
    return next((c for c in st["instances"] if c["name"] == n), None)


rc = 0
v = a[0] if a else ""
if tool == "lxd":
    if v == "init":
        try:
            os.remove(os.path.join(D, "uninitialised"))
        except FileNotFoundError:
            pass
        print("LXD is configured")
    else:
        print("lxd: unknown command: %s" % v, file=sys.stderr)
        rc = 1
elif v == "list":
    if os.path.exists(os.path.join(D, "uninitialised")):
        print("Error: LXD has not been properly initialized", file=sys.stderr)
        rc = 1
    else:
        print(json.dumps(st["instances"]))
elif v == "launch" and len(a) >= 3:
    st["instances"].append(
        {
            "name": a[2],
            "status": "RUNNING",
            "image": a[1],
            "type": "container",
            "address": "10.0.0.20",
        }
    )
    save()
elif v in ("start", "stop", "restart") and len(a) >= 2:
    c = find(a[1])
    if c:
        c["status"] = "STOPPED" if v == "stop" else "RUNNING"
        save()
elif v == "delete" and len(a) >= 2:
    st["instances"] = [c for c in st["instances"] if c["name"] != a[1]]
    save()
elif v == "exec":
    pass  # a shell in the instance changes nothing here
else:
    print("lxc: unknown command: %s" % v, file=sys.stderr)
    rc = 1
sys.exit(rc)
