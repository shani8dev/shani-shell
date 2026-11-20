#!/usr/bin/env python3
"""Stands in for podman and distrobox (tests/test_containers.py, dev/shell-parts/
containers.sh): containers and images kept in $FAKE_PODMAN/state.json, answered in
podman's own JSON shapes; distrobox create/rm/upgrade/enter act on the same state."""
import json, os, sys, time, traceback
def _logged(t, v, tb):        # a failure of the stand-in itself, for the part to show
    with open(os.path.join(os.environ.get("FAKE_PODMAN", "/tmp"), "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))
sys.excepthook = _logged
D = os.environ["FAKE_PODMAN"]; S = os.path.join(D, "state.json")
st = json.load(open(S)) if os.path.exists(S) else {
    "containers": [{"Id": "aaa111", "Names": ["web"], "Image": "docker.io/library/nginx:latest", "State": "running", "Created": 1, "Labels": {}, "Ports": [{"host_port": 8080, "container_port": 80}]}],
    "images": [{"Id": "img1111111", "Names": ["docker.io/library/nginx:latest"], "Size": 190000000, "Created": 1},
               {"Id": "img2222222", "Names": ["docker.io/library/old:1"], "Size": 50000000, "Created": 1}]}
prog = os.path.basename(sys.argv[0]); a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(prog + " " + " ".join(a) + "\n")
def save(): json.dump(st, open(S, "w"))
def find(n): return next((c for c in st["containers"] if n in c["Names"]), None)
if prog.startswith("distrobox"):
    if a[0] == "create":
        n = a[a.index("--name") + 1]; img = a[a.index("--image") + 1]
        for p in ("Pulling image", "Creating", "Distrobox created"): print(p); sys.stdout.flush(); time.sleep(0.2)
        st["containers"].append({"Id": "box" + n, "Names": [n], "Image": img, "State": "exited", "Created": 2, "Labels": {"manager": "distrobox"}, "Ports": []})
        if not any(img in i["Names"] for i in st["images"]):      # pulled, as distrobox does
            st["images"].append({"Id": "img" + str(len(st["images"]) + 1) * 7, "Names": [img], "Size": 400000000, "Created": 2})
        save()
    elif a[0] == "rm":
        st["containers"] = [c for c in st["containers"] if a[-1] not in c["Names"]]; save()
    elif a[0] == "upgrade": print("Upgrading..."); print("done")
    elif a[0] == "enter": open(os.path.join(D, "exported"), "a").write(a[-1] + "\n")
    sys.exit(0)
if a[:2] == ["ps", "-a"]: print(json.dumps(st["containers"]))
elif a[:1] == ["images"]: print(json.dumps(st["images"]))
elif a[0] in ("start", "restart"): c = find(a[-1]); c["State"] = "running"; save()
elif a[0] == "stop": c = find(a[-1]); c["State"] = "exited"; save()
elif a[0] == "rm": st["containers"] = [c for c in st["containers"] if a[-1] not in c["Names"]]; save()
elif a[0] == "logs": print("line one\nline two")
elif a[0] == "rmi": st["images"] = [i for i in st["images"] if not i["Id"].startswith(a[-1])]; save()
elif a[:2] == ["image", "prune"]:
    used = {c["Image"] for c in st["containers"]}
    gone = [i for i in st["images"] if not set(i["Names"]) & used]; st["images"] = [i for i in st["images"] if i not in gone]; save()
    for i in gone: print(i["Id"])
elif a[0] == "exec": print("org.gnome.gedit.desktop\tText Editor\nfirefox.desktop\tFirefox")
