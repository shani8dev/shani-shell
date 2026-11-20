"""bridge/flatperm.py against a stand-in flatpak that keeps overrides the way the
real one does (a keyfile per app): Flatseal's sections read, a change written
as `flatpak override --user` and marked as yours, portals' answers, reset; and
nothing but override's own flags passed on."""

import json
import os
import subprocess
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parent.parent / "bridge" / "flatperm.py"
FAKE = r"""#!/usr/bin/env python3
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
"""


def run(tmp_path, *args):
    fake = tmp_path / "flatpak"
    if not fake.exists():
        fake.write_text(FAKE)
        fake.chmod(0o755)
    env = dict(os.environ, SHANI_FLATPAK=str(fake), FAKE_FP=str(tmp_path))
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *args], capture_output=True, text=True, env=env
    )
    return json.loads(r.stdout), r.returncode


def test_reads_flatseals_sections(tmp_path):
    apps, _ = run(tmp_path, "apps")
    assert [a["name"] for a in apps] == ["Example", "Tool"]
    p, rc = run(tmp_path, "show", "org.example.App")
    assert (
        rc == 0
        and p["shared"] == ["network", "ipc"]
        and "pulseaudio" in p["sockets"]
        and p["devices"] == ["dri"]
    )
    assert (
        p["filesystems"] == ["xdg-download"]
        and p["changed"] == {}
        and p["portals"] == {}
    )


def test_changes_are_yours_and_reset(tmp_path):
    p, rc = run(
        tmp_path,
        "set",
        "org.example.App",
        "--unshare=network",
        "--socket=x11",
        "--filesystem=~/Music:ro",
        "--env=GTK_THEME=Adwaita:dark",
        "--talk-name=org.freedesktop.Flatpak",
    )
    assert (
        rc == 0
        and "network" not in p["shared"]
        and "x11" in p["sockets"]
        and "~/Music:ro" in p["filesystems"]
    )
    assert p["env"] == {"GTK_THEME": "Adwaita:dark"} and p["session"] == {
        "org.freedesktop.Flatpak": "talk"
    }
    assert set(p["changed"]) == {
        "shared",
        "sockets",
        "filesystems",
        "env",
        "session",
    } and p["changed"]["shared"] == ["network"]
    p, _ = run(tmp_path, "reset", "org.example.App")
    assert p["shared"] == ["network", "ipc"] and p["changed"] == {}


def test_portals(tmp_path):
    p, _ = run(tmp_path, "portal", "org.example.App", "notifications", "no")
    assert p["portals"] == {"notifications": "no"}
    p, _ = run(tmp_path, "portal", "org.example.App", "camera", "yes")
    assert p["portals"] == {"notifications": "no", "camera": "yes"}
    p, _ = run(tmp_path, "portal", "org.example.App", "notifications", "reset")
    assert p["portals"] == {"camera": "yes"}
    assert "devices camera org.example.App yes" in (tmp_path / "calls").read_text()


def test_only_overrides_own_flags(tmp_path):
    p, rc = run(tmp_path, "set", "org.example.App", "--socket=x11", "; rm -rf ~")
    assert rc == 1 and "not a permission" in p["error"]
    p, rc = run(tmp_path, "set", "org.example.App", "--reset")
    assert rc == 1
    # an in-process rejection must not call flatpak at all: no log is written
    assert not (tmp_path / "calls").exists()
