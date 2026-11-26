#!/usr/bin/env python3
"""Stands in for machinectl, importctl and systemd-vmspawn (tests and dev/shell-
parts/containers.sh): machines/images kept in $FAKE_PODMAN/machines.json; calls and
failures go to the same $FAKE_PODMAN/calls and /errors the podman stand-in uses.
The tool comes from the name it is run as, or FAKE_MACHINE_TOOL when that name is
generic (aliases such as machinectl.py and fake-machinectl are accepted)."""
import json, os, sys, traceback
def _logged(t, v, tb):
    with open(os.path.join(os.environ.get("FAKE_PODMAN", "/tmp"), "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))
sys.excepthook = _logged
D = os.environ["FAKE_PODMAN"]; S = os.path.join(D, "machines.json")
def blank():
    return {
        "machines": [{"Name": "archlinux", "Class": "systemd-nspawn", "Service": "systemd-nspawn@archlinux.service", "State": "running"}],
        "images": [{"Name": "archlinux", "Type": "raw/directory", "Size": "1.2G", "Created": 1},
                   {"Name": "fedora", "Type": "raw/directory", "Size": "900M", "Created": 1}]}
st = json.load(open(S)) if os.path.exists(S) else blank()
TOOLS = ("machinectl", "importctl", "systemd-vmspawn")
def canon(s):
    s = s.lower()
    if s.endswith(".py"): s = s[:-3]
    if s.startswith("fake-"): s = s[5:]
    return s
name = canon(os.environ.get("FAKE_MACHINE_TOOL") or os.path.basename(sys.argv[0]))
if name == "vmspawn": name = "systemd-vmspawn"
if name not in TOOLS: name = next((t for t in TOOLS if t in name), "machinectl")
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(name + " " + " ".join(a) + "\n")
def save(): json.dump(st, open(S, "w"))
def find(lst, n): return next((x for x in lst if x["Name"] == n), None)
def created(): return max([x.get("Created", 0) for k in ("machines", "images") for x in st[k]] + [0]) + 1
rc = 0
if name == "machinectl":
    v = a[0] if a else ""
    if v == "list":
        print("MACHINE CLASS SERVICE OS VERSION ADDRESSES")
        for m in st["machines"]: print(" ".join([m["Name"], m["Class"], "-", "-", "-", "-"]))
    elif v == "list-images":
        print("NAME TYPE SIZE CREATED MODIFIED")
        for i in st["images"]: print(" ".join([i["Name"], i["Type"], i["Size"], "-", "-"]))
    elif v in ("start", "poweroff", "reboot", "stop"):
        m = find(st["machines"], a[-1])
        if m: m["State"] = "running" if v == "start" else "exited"; save()
    elif v == "shell": pass                 # a shell in the machine changes nothing here
    elif v == "remove":
        st["images"] = [i for i in st["images"] if i["Name"] != a[-1]]
        st["machines"] = [m for m in st["machines"] if m["Name"] != a[-1]]; save()
    elif v == "clone":
        src = find(st["images"], a[1])
        if src: st["images"].append(dict(src, Name=a[2], Created=created())); save()
    elif v == "rename":
        old, new = a[1], a[2]
        i = find(st["images"], old)
        if i: i["Name"] = new
        m = find(st["machines"], old)
        if m: m["Name"] = new
        save()
    else:
        print("machinectl: unknown command: %s" % v, file=sys.stderr); rc = 1
elif name == "importctl":
    v = a[0] if a else ""
    if v in ("pull-tar", "pull-raw"):
        url, img = a[1], a[2]
        print("Pulling " + url); sys.stdout.flush()
        st["images"].append({"Name": img, "Type": "tar" if v == "pull-tar" else "raw", "Size": "1.0G", "Created": created()}); save()
        print("Imported " + img); sys.stdout.flush()
    else:
        print("importctl: unknown command: %s" % v, file=sys.stderr); rc = 1
else:
    if "--image" in a:
        print("Booting " + a[a.index("--image") + 1]); sys.stdout.flush()
    else:
        print("systemd-vmspawn: --image is required", file=sys.stderr); rc = 1
sys.exit(rc)
