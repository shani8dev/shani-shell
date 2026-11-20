#!/usr/bin/env python3
# stands in for flatpak: two apps, overrides kept as the real one keeps them (shared with tests/test_flatperm.py)
import os, sys, json
D = os.environ["FAKE_FP"]; a = sys.argv[1:]
ov = os.path.join(D, "override.json")
o = json.load(open(ov)) if os.path.exists(ov) else {}
open(os.path.join(D, "calls"), "a").write(" ".join(a) + "\n")
ASKED = {"shared": ["network", "ipc"], "sockets": ["wayland", "fallback-x11", "pulseaudio"], "devices": ["dri"], "filesystems": ["xdg-download"]}
def kf(d, envs=None, talk=None):
    s = "[Context]\n" + "".join("%s=%s;\n" % (k, ";".join(v)) for k, v in d.items() if v)
    if talk: s += "\n[Session Bus Policy]\n" + "".join("%s=%s\n" % kv for kv in talk.items())
    if envs: s += "\n[Environment]\n" + "".join("%s=%s\n" % kv for kv in envs.items())
    return s
def eff():
    d = {k: list(v) for k, v in ASKED.items()}
    for k, v in o.get("ctx", {}).items():
        for x in v:
            name = x.lstrip("!")
            d.setdefault(k, [])
            if x.startswith("!"):
                d[k] = [y for y in d[k] if y != name]
            elif name not in d[k]:
                d[k].append(name)
    return d
if a[:2] == ["list", "--app"]: print("org.example.App\tExample\nio.other.Tool\tTool")
elif a[:2] == ["info", "--show-permissions"]: print(kf(eff(), o.get("env"), o.get("talk")))
elif a[:3] == ["override", "--user", "--show"]: print(kf(o.get("ctx", {}), o.get("env"), o.get("talk")))
elif a[:3] == ["override", "--user", "--reset"]: o = {}
elif a[:2] == ["override", "--user"]:
    for f in a[2:-1]:
        k, _, v = f[2:].partition("=")
        m = {"share": ("shared", ""), "unshare": ("shared", "!"), "socket": ("sockets", ""), "nosocket": ("sockets", "!"),
             "device": ("devices", ""), "nodevice": ("devices", "!"), "filesystem": ("filesystems", ""), "nofilesystem": ("filesystems", "!"),
             "allow": ("features", ""), "disallow": ("features", "!")}
        if k in m:
            sec, neg = m[k]; lst = o.setdefault("ctx", {}).setdefault(sec, [])
            lst[:] = [x for x in lst if x.lstrip("!") != v] + [neg + v]
        elif k == "env": n, _, val = v.partition("="); o.setdefault("env", {})[n] = val
        elif k == "talk-name": o.setdefault("talk", {})[v] = "talk"
elif a[0] == "permission-show": print("Table Object App Permissions Data\n" + "".join("%s %s %s %s\n" % (t, i, a[1], p) for (t, i), p in o.get("perm", {}).items()) if False else "Table Object App Permissions Data\n" + "".join("%s %s %s %s\n" % (k.split("|")[0], k.split("|")[1], a[1], p) for k, p in o.get("perm", {}).items()))
elif a[0] == "permission-set": o.setdefault("perm", {})["%s|%s" % (a[1], a[2])] = a[4]
elif a[0] == "permission-remove": o.get("perm", {}).pop("%s|%s" % (a[1], a[2]), None)
json.dump(o, open(ov, "w"))
