#!/usr/bin/env python3
"""Stands in for virsh and virt-viewer ($FAKE_VIRSH): session/system domains kept
in domains.json. Calls and failures go to calls and errors in that dir. The tool
comes from the name it is run as, or FAKE_VIRSH_TOOL."""

import json, os, sys, traceback

D = os.environ["FAKE_VIRSH"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
os.makedirs(D, exist_ok=True)
S = os.path.join(D, "domains.json")


def blank():
    return {
        "session": [{"name": "dev-vm", "state": "running"}],
        "system": [{"name": "server-vm", "state": "shut off"}],
    }


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


name = canon(os.environ.get("FAKE_VIRSH_TOOL") or os.path.basename(sys.argv[0]))
tool = "virt-viewer" if "viewer" in name else "virsh"
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(tool + " " + " ".join(a) + "\n")


def save():
    json.dump(st, open(S, "w"))


def find(key, n):
    return next((d for d in st[key] if d["name"] == n), None)


if tool == "virt-viewer":
    sys.exit(0)  # a viewer window changes nothing here
args = []
uri = "qemu:///session"
i = 0
while i < len(a):
    if a[i] in ("-c", "--connect"):
        uri = a[i + 1]
        i += 2
    elif a[i].startswith("--connect="):
        uri = a[i].split("=", 1)[1]
        i += 1
    else:
        args.append(a[i])
        i += 1
key = "system" if "system" in uri else "session"
rc = 0
v = args[0] if args else ""
if v == "uri":
    print("qemu:///session")
elif v == "list":
    for d in st[key]:
        print(d["name"])
elif v in ("start", "shutdown", "destroy", "reboot") and len(args) > 1:
    d = find(key, args[1])
    if d:
        d["state"] = "shut off" if v in ("shutdown", "destroy") else "running"
        save()
elif v == "console":
    pass  # a console session changes nothing here
elif v == "undefine" and len(args) > 1:
    st[key] = [d for d in st[key] if d["name"] != args[1]]
    save()
    with open(os.path.join(D, "undefined"), "a") as f:
        f.write(args[1] + "|" + ("1" if "--remove-all-storage" in args else "0") + "\n")
else:
    print("virsh: unknown command: %s" % v, file=sys.stderr)
    rc = 1
sys.exit(rc)
