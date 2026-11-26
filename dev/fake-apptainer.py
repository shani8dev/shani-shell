#!/usr/bin/env python3
"""Stands in for apptainer ($FAKE_APPTAINER): .sif images live in images/ and are
listed in state.json. Calls and failures go to calls and errors in that dir. The
tool comes from the name it is run as, or FAKE_APPTAINER_TOOL."""

import json, os, sys, traceback

D = os.environ["FAKE_APPTAINER"]


def _logged(t, v, tb):
    with open(os.path.join(D, "errors"), "a") as f:
        f.write("".join(traceback.format_exception(t, v, tb)))


sys.excepthook = _logged
os.makedirs(D, exist_ok=True)
S = os.path.join(D, "state.json")
IM = os.path.join(D, "images")
os.makedirs(IM, exist_ok=True)


def blank():
    return {"images": ["ubuntu_22.04.sif", "python_3.11.sif"]}


st = json.load(open(S)) if os.path.exists(S) else blank()
st.setdefault("images", blank()["images"])


def write_image(n):
    with open(os.path.join(IM, n), "wb") as f:
        f.write(b"fake sif\n" * 128)


for n in st["images"]:
    if not os.path.exists(os.path.join(IM, n)):
        write_image(n)
if not os.path.exists(S):
    json.dump(st, open(S, "w"))


def canon(s):
    s = s.lower()
    if s.endswith(".py"):
        s = s[:-3]
    if s.startswith("fake-"):
        s = s[5:]
    return s


name = canon(os.environ.get("FAKE_APPTAINER_TOOL") or os.path.basename(sys.argv[0]))
a = sys.argv[1:]
open(os.path.join(D, "calls"), "a").write(name + " " + " ".join(a) + "\n")


def save():
    json.dump(st, open(S, "w"))


def target():
    return a[1] if len(a) > 1 else ""


rc = 0
v = a[0] if a else ""
if v == "pull":
    nm = (
        a[a.index("--name") + 1]
        if "--name" in a
        else next((x[7:] for x in a if x.startswith("--name=")), "")
    )
    ref = a[-1] if a else ""
    if not ref.startswith(("docker://", "oras://")):
        print("apptainer: unsupported reference: %s" % ref, file=sys.stderr)
        rc = 1
    else:
        nm = nm or (ref.rstrip("/").split("/")[-1] + ".sif")
        print("Pulling " + ref)
        sys.stdout.flush()
        write_image(nm)
        if nm not in st["images"]:
            st["images"].append(nm)
            save()
        print("Saved " + nm)
        sys.stdout.flush()
elif v in ("run", "shell"):
    print("Running " + target() if v == "run" else "Shell in " + target())
elif v == "delete":
    n = os.path.basename(target())
    if os.path.exists(os.path.join(IM, n)):
        os.remove(os.path.join(IM, n))
    st["images"] = [i for i in st["images"] if i != n]
    save()
else:
    print("apptainer: unknown command: %s" % v, file=sys.stderr)
    rc = 1
sys.exit(rc)
