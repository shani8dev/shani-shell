#!/usr/bin/env python3
"""Stands in for podman and distrobox (tests/test_containers.py, dev/shell-parts/
containers.sh): containers/images/pods/volumes kept in $FAKE_PODMAN/state.json,
answered in podman's own JSON shapes; distrobox create/rm/upgrade/enter act on the
same state."""

import json, os, sys, time, traceback


def _logged(t, v, tb):  # a failure of the stand-in itself, for the part to show
    with open(os.path.join(os.environ.get("FAKE_PODMAN", "/tmp"), "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
D = os.environ["FAKE_PODMAN"]
S = os.path.join(D, "state.json")


def blank():
    return {
        "containers": [
            {
                "Id": "aaa111",
                "Names": ["web"],
                "Image": "docker.io/library/nginx:latest",
                "State": "running",
                "Created": 1,
                "Labels": {},
                "Ports": [{"host_port": 8080, "container_port": 80}],
            }
        ],
        "images": [
            {
                "Id": "img1111111",
                "Names": ["docker.io/library/nginx:latest"],
                "Size": 190000000,
                "Created": 1,
            },
            {
                "Id": "img2222222",
                "Names": ["docker.io/library/old:1"],
                "Size": 50000000,
                "Created": 1,
            },
        ],
        "pods": [
            {
                "Name": "webpod",
                "ID": "pod111",
                "Status": "running",
                "Containers": 1,
                "Created": 1,
            }
        ],
        "volumes": [{"Name": "site", "Driver": "local", "Size": 1234567, "Created": 1}],
    }


st = json.load(open(S)) if os.path.exists(S) else blank()
for k in ("pods", "volumes"):
    st.setdefault(k, blank()[k])
prog = os.path.basename(sys.argv[0])
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(prog + " " + " ".join(a) + "\n")


def save():
    json.dump(st, open(S, "w"))


def find(n):
    return next((c for c in st["containers"] if n in c["Names"]), None)


def created():
    return (
        max(
            [
                x.get("Created", 0)
                for k in ("containers", "images", "pods", "volumes")
                for x in st[k]
            ]
            + [0]
        )
        + 1
    )


def num(x):
    return int(x) if x.isdigit() else x


def port(spec):
    h, _, c = spec.partition(":")
    return {"host_port": num(h), "container_port": num(c)}


if prog.startswith("distrobox"):
    if a[0] == "create":
        n = a[a.index("--name") + 1]
        img = a[a.index("--image") + 1]
        for p in ("Pulling image", "Creating", "Distrobox created"):
            print(p)
            sys.stdout.flush()
            time.sleep(0.2)
        st["containers"].append(
            {
                "Id": "box" + n,
                "Names": [n],
                "Image": img,
                "State": "exited",
                "Created": 2,
                "Labels": {"manager": "distrobox"},
                "Ports": [],
            }
        )
        if not any(
            img in i["Names"] for i in st["images"]
        ):  # pulled, as distrobox does
            st["images"].append(
                {
                    "Id": "img" + str(len(st["images"]) + 1) * 7,
                    "Names": [img],
                    "Size": 400000000,
                    "Created": 2,
                }
            )
        save()
    elif a[0] == "rm":
        st["containers"] = [c for c in st["containers"] if a[-1] not in c["Names"]]
        save()
    elif a[0] == "clone":
        src = find(a[1])
        if src:
            st["containers"].append(
                dict(src, Id="box" + a[2], Names=[a[2]], Created=created())
            )
            save()
    elif a[0] == "upgrade":
        print("Upgrading...")
        print("done")
    elif a[0] == "enter":
        tail = a[a.index("--") + 1 :] if "--" in a else a[1:]
        if tail and tail[0] == "distrobox-export":  # only an export touches the menu
            app = tail[tail.index("--app") + 1] if "--app" in tail else tail[-1]
            open(os.path.join(D, "exported"), "a").write(app + "\n")
        elif tail:
            pkg = next((t for t in tail if t.endswith((".deb", ".rpm"))), tail[-1])
            print("Installing " + pkg)
            print("Done")
    sys.exit(0)
if a[:2] == ["ps", "-a"]:
    print(json.dumps(st["containers"]))
elif a[:1] == ["images"]:
    print(json.dumps(st["images"]))
elif a[0] in ("start", "restart"):
    c = find(a[-1])
    c["State"] = "running"
    save()
elif a[0] == "stop":
    c = find(a[-1])
    c["State"] = "exited"
    save()
elif a[0] in ("pause", "unpause", "kill"):
    c = find(a[-1])
    if c:
        c["State"] = {"pause": "paused", "unpause": "running", "kill": "exited"}[a[0]]
        save()
elif a[0] == "rm":
    st["containers"] = [c for c in st["containers"] if a[-1] not in c["Names"]]
    save()
elif a[0] == "rename":
    c = find(a[1])
    if c:
        c["Names"][0] = a[2]
        save()
elif a[0] == "run":
    name = ""
    ps = []
    ms = []
    es = []
    img = ""
    cmd = []
    i = 1
    while i < len(a):
        t = a[i]
        if t == "--name":
            name = a[i + 1]
            i += 2
        elif t in ("-p", "--publish", "-v", "--volume", "-e", "--env"):
            v = a[i + 1]
            i += 2
            (
                ps
                if t in ("-p", "--publish")
                else ms
                if t in ("-v", "--volume")
                else es
            ).append(v)
        elif t.startswith("-p") and len(t) > 2:
            ps.append(t[2:])
            i += 1
        elif t.startswith("-v") and len(t) > 2:
            ms.append(t[2:])
            i += 1
        elif t.startswith("-e") and len(t) > 2:
            es.append(t[2:])
            i += 1
        elif t in ("--device", "--security-opt"):
            i += 2  # GPU flags carry a value, not an image
        elif t.startswith("-"):
            i += 1
        elif not img:
            img = t
            i += 1
        else:
            cmd.append(t)
            i += 1
    n = created()
    lab = {}
    if es:
        lab["env"] = " ".join(es)
    if cmd:
        lab["command"] = " ".join(cmd)
    st["containers"].append(
        {
            "Id": "c" + str(n),
            "Names": [name or img],
            "Image": img,
            "State": "running",
            "Created": n,
            "Labels": lab,
            "Ports": [port(p) for p in ps],
            "Cmd": cmd,
            "Env": es,
            "Mounts": [
                {
                    "Source": m.split(":")[0],
                    "Destination": m.split(":")[1] if ":" in m else m,
                }
                for m in ms
            ],
        }
    )
    save()
    print(name or img)
elif a[0] == "commit":
    n = created()
    iid = "img" + str(n) * 7
    st["images"].append({"Id": iid, "Names": [a[2]], "Size": 100000000, "Created": n})
    save()
    print(iid[:12])
elif a[0] == "build":
    tag = a[a.index("-t") + 1] if "-t" in a else a[-1]
    for p in (
        "Step 1/2 : FROM alpine",
        "Step 2/2 : COPY . /app",
        "Successfully built " + tag,
    ):
        print(p)
        sys.stdout.flush()
    n = created()
    st["images"].append(
        {"Id": "img" + str(n) * 7, "Names": [tag], "Size": 1234567, "Created": n}
    )
    save()
elif a[0] == "stats":
    for c in st["containers"]:
        if "--all" in a or (c["Names"] and c["Names"][0] == a[-1]):
            print((c["Names"][0] if c["Names"] else "") + "|12.5%|10MiB / 1GiB")
elif a[0] == "inspect":
    c = find(a[-1]) or {}
    hp = c.get("Ports") or []
    nd = {}
    for p in hp:
        nd[str(p.get("container_port")) + "/tcp"] = [
            {"HostIp": "0.0.0.0", "HostPort": str(p.get("host_port"))}
        ]
    print(
        json.dumps(
            [
                {
                    "Name": (c.get("Names") or [""])[0],
                    "Id": c.get("Id", ""),
                    "State": {"Status": c.get("State", "")},
                    "Image": c.get("Image", ""),
                    "Created": c.get("Created", 0),
                    "Config": {"Cmd": c.get("Cmd", []), "Env": c.get("Env", [])},
                    "Mounts": c.get("Mounts", []),
                    "NetworkSettings": {"Ports": nd},
                    "Ports": [
                        {
                            "HostIp": "0.0.0.0",
                            "HostPort": str(p.get("host_port")),
                            "ContainerPort": str(p.get("container_port")),
                        }
                        for p in hp
                    ],
                }
            ]
        )
    )
elif a[0] == "search":
    term = a[-1]
    try:
        n = int(a[a.index("--limit") + 1]) if "--limit" in a else 3
    except ValueError:
        n = 3
    rs = [
        {
            "name": "docker.io/library/" + term,
            "description": "Official " + term + " image",
            "stars": 123,
            "official": True,
        },
        {
            "name": "docker.io/" + term + "/community",
            "description": "Community " + term + " build",
            "stars": 42,
            "official": False,
        },
        {
            "name": "docker.io/other/" + term,
            "description": "Another " + term + " build",
            "stars": 7,
            "official": False,
        },
    ]
    print(json.dumps(rs[: max(n, 2)]))
elif a[0] == "pull":
    img = a[-1]
    print("Pulling " + img)
    sys.stdout.flush()
    if not any(img in i["Names"] for i in st["images"]):
        n = created()
        st["images"].append(
            {"Id": "img" + str(n) * 7, "Names": [img], "Size": 400000000, "Created": n}
        )
        save()
    print("Downloaded " + img)
    sys.stdout.flush()
elif a[0] == "logs":
    print("follow one\nfollow two") if "--follow" in a else print("line one\nline two")
elif a[:1] == ["pod"]:
    if a[1] == "ps":
        print(json.dumps(st["pods"]))
    elif a[1] in ("start", "stop"):
        p = next((p for p in st["pods"] if p["Name"] == a[-1]), None)
        if p:
            p["Status"] = "running" if a[1] == "start" else "exited"
            save()
    elif a[1] == "rm":
        st["pods"] = [p for p in st["pods"] if p["Name"] != a[-1]]
        save()
elif a[:1] == ["volume"]:
    if a[1] == "ls":
        print(json.dumps(st["volumes"]))
    elif a[1] == "create":
        n = created()
        st["volumes"].append(
            {"Name": a[-1], "Driver": "local", "Size": 0, "Created": n}
        )
        save()
        print(a[-1])
    elif a[1] == "rm":
        st["volumes"] = [v for v in st["volumes"] if v["Name"] != a[-1]]
        save()
    elif a[1] == "prune":
        used = {m["Source"] for c in st["containers"] for m in c.get("Mounts", [])}
        gone = [v for v in st["volumes"] if v["Name"] not in used]
        st["volumes"] = [v for v in st["volumes"] if v not in gone]
        save()
        for v in gone:
            print(v["Name"])
elif a[0] == "rmi":
    st["images"] = [i for i in st["images"] if not i["Id"].startswith(a[-1])]
    save()
elif a[:2] == ["image", "prune"]:
    used = {c["Image"] for c in st["containers"]}
    gone = [i for i in st["images"] if not set(i["Names"]) & used]
    st["images"] = [i for i in st["images"] if i not in gone]
    save()
    for i in gone:
        print(i["Id"])
elif a[0] == "cp":
    try:
        with open(a[2], "w") as f:
            f.write("copied from " + a[1] + "\n")
    except OSError:
        pass
elif a[0] == "exec":
    if len(a) > 2 and a[2] == "ls":
        print("total 2")
        print("-rw-r--r-- 1 root root 12 Jan  1 00:00 notes.txt")
        print("drwxr-xr-x 2 root root 40 Jan  1 00:00 docs")
    else:
        print("org.gnome.gedit.desktop\tText Editor\nfirefox.desktop\tFirefox")
