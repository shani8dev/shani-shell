#!/usr/bin/env python3
"""system_machine — read-only facts about the machine behind the system pages.

    system_machine.py graphics           {"have": {"lspci": bool},
                                          "devices": [{"name", "driver", "vendor"}],
                                          "render": ["/dev/dri/renderD128"], "gl": ""}
    system_machine.py etc-list           {"ok", "changes": [{"path", "kind", "protected",
                                          "secret", "pending"}], "pending", "done", "error"}
    system_machine.py etc-diff PATH      {"ok", "diff", "hidden", "binary", "error"}
    system_machine.py etc-restore PATH   {"ok", "queued", "error"}
    system_machine.py etc-cancel PATH    {"ok", "queued", "error"}
    system_machine.py persistence        {"mounts": [{"path", "source", "note"}],
                                          "data": [{"path", "size"}], "error": ""}

Graphics, etc changes and persistence are read as the user; a missing tool or a
helper that fails is reported honestly, never as invented rows. Restoring or
cancelling a system change only queues it through the machine's own privileged
helper, and only after the path passes strict validation. Persistence never
writes anything. SHANI_LSPCI, SHANI_GLXINFO, SHANI_SYSTEM_DRI_DIR, SHANI_ETC_CHANGES,
SHANI_MOUNTINFO, SHANI_DATA_DIR and SHANI_DATA_SIZE are stand-ins in the tests.
Every command has a 30-second limit.
"""

from __future__ import annotations

import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

TIMEOUT = 30
LSPCI = shlex.split(os.environ.get("SHANI_LSPCI", "lspci"))
GLXINFO = shlex.split(os.environ.get("SHANI_GLXINFO", "glxinfo"))
ETC = shlex.split(
    os.environ.get("SHANI_ETC_CHANGES", "pkexec /usr/local/bin/shani-etc-changes")
)
DRI_DIR = os.environ.get("SHANI_SYSTEM_DRI_DIR", "/dev/dri")
MOUNTINFO = os.environ.get("SHANI_MOUNTINFO", "/proc/self/mountinfo")
DATA_DIR = os.environ.get("SHANI_DATA_DIR", "/data")
DATA_SIZE = os.environ.get("SHANI_DATA_SIZE", "") == "1"

PATH_OK = re.compile(r"^/[A-Za-z0-9._+/-]{1,199}$")
CLASSES = ("VGA compatible controller", "3D controller", "Display controller")
PCI_VENDOR = {
    "8086": "Intel Corporation",
    "10de": "NVIDIA Corporation",
    "1002": "AMD",
    "102b": "Matrox",
    "106b": "Apple",
    "15ad": "VMware",
    "1af4": "Red Hat",
}
PCI_ID = re.compile(r"\s+\[([0-9a-fA-F]{4}):[0-9a-fA-F]{4}\]")
ADDRESS = re.compile(r"^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]\s+")


def _have(cmd: list[str]) -> bool:
    return shutil.which(cmd[0]) is not None


def _run(cmd: list[str], *args: str) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            cmd + list(args), capture_output=True, text=True, timeout=TIMEOUT
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 1, "", str(e))


# ---- graphics: one lspci read, the render nodes and the renderer ------------------
def _devices(text: str) -> list[dict]:
    out = []
    # lspci often prints its blocks back to back, with no blank line between
    # them: each new PCI address starts a device, not each empty line.
    blocks = []
    for line in text.splitlines():
        if ADDRESS.match(line):
            blocks.append([line])
        elif blocks:
            blocks[-1].append(line)
    for block in blocks:
        lines = [l.strip() for l in block if l.strip()]
        if not lines:
            continue
        body = ADDRESS.sub("", lines[0])
        if not any(body.startswith(c) for c in CLASSES):
            continue
        name = body.split(":", 1)[1].strip() if ":" in body else body
        m = PCI_ID.search(name)
        ident = m.group(1).lower() if m else ""
        name = PCI_ID.sub("", name)
        name = re.sub(r"\s+\(rev [^)]*\)$", "", name).strip()
        driver = next(
            (
                l.split(":", 1)[1].strip()
                for l in lines[1:]
                if l.startswith("Kernel driver in use:")
            ),
            "",
        )
        out.append(
            {
                "name": name,
                "driver": driver,
                "vendor": PCI_VENDOR.get(ident) or (name.split()[0] if name else ""),
            }
        )
    return out


def _gl() -> str:
    if not _have(GLXINFO):
        return ""
    for line in _run(GLXINFO, "-B").stdout.splitlines():
        s = line.strip()
        if s.startswith("OpenGL renderer string:"):
            return s.split(":", 1)[1].strip()
    return ""


def graphics() -> dict:
    have = _have(LSPCI)
    return {
        "have": {"lspci": have},
        "devices": _devices(_run(LSPCI, "-nnk").stdout) if have else [],
        "render": sorted(glob.glob(os.path.join(DRI_DIR, "renderD*"))),
        "gl": _gl(),
    }


# ---- system changes: the machine's own privileged helper --------------------------
def _etc_json(*args: str) -> tuple[dict | list | None, str]:
    r = _run(ETC, *args)
    if r.returncode != 0:
        lines = r.stderr.strip().splitlines() or r.stdout.strip().splitlines()
        return None, (lines or ["the system change helper failed"])[-1]
    try:
        return json.loads(r.stdout or "{}"), ""
    except ValueError:
        return None, "the system change helper did not answer with JSON"


def _bad_path(path: str) -> str:
    if not isinstance(path, str) or not PATH_OK.match(path) or ".." in path:
        return "not a path this machine will touch"
    return ""


def etc_list() -> dict:
    out = {"ok": False, "changes": [], "pending": [], "done": [], "error": ""}
    data, error = _etc_json("list", "--json")
    if data is None:
        out["error"] = error
        return out
    rows = (
        data
        if isinstance(data, list)
        else (data.get("changes", []) if isinstance(data, dict) else [])
    )
    for row in rows:
        if isinstance(row, dict):
            out["changes"].append(
                {
                    "path": str(row.get("path") or ""),
                    "kind": str(row.get("kind") or ""),
                    "protected": bool(row.get("protected")),
                    "secret": bool(row.get("secret")),
                    "pending": bool(row.get("pending")),
                }
            )
    for key in ("pending", "done"):
        value = data.get(key, []) if isinstance(data, dict) else []
        out[key] = [str(x) for x in value] if isinstance(value, list) else []
    if isinstance(data, dict):
        out["ok"] = bool(data.get("ok", True))
        out["error"] = str(data.get("error") or "")
    else:
        out["ok"] = True
    return out


def etc_diff(path: str) -> dict:
    out = {"ok": False, "diff": "", "hidden": False, "binary": False, "error": ""}
    bad = _bad_path(path)
    if bad:
        out["error"] = bad
        return out
    data, error = _etc_json("diff", path)
    if data is None:
        out["error"] = error
    elif not isinstance(data, dict):
        out["error"] = "the helper did not answer with a file change"
    else:
        out.update(
            {
                "ok": bool(data.get("ok", True)),
                "diff": str(data.get("diff") or ""),
                "hidden": bool(data.get("hidden")),
                "binary": bool(data.get("binary")),
                "error": str(data.get("error") or ""),
            }
        )
    return out


def etc_queue(verb: str, path: str) -> dict:
    out = {"ok": False, "queued": False, "error": ""}
    bad = _bad_path(path)
    if bad:
        out["error"] = bad
        return out
    data, error = _etc_json(verb, path)
    if data is None:
        out["error"] = error
    elif not isinstance(data, dict):
        out["error"] = "the helper did not answer with a queue result"
    else:
        out.update(
            {
                "ok": bool(data.get("ok", True)),
                "queued": bool(data.get("queued")),
                "error": str(data.get("error") or ""),
            }
        )
    return out


# ---- persistence: what lives under /data and is mounted into /var -----------------
def _mounts() -> tuple[list[dict], str]:
    out = []
    try:
        with open(MOUNTINFO, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError as e:
        return out, str(e)
    for line in lines:
        f = line.split()
        if len(f) < 5:
            continue
        source, target = f[3], f[4]
        if not (target == "/var" or target.startswith("/var/")):
            continue
        if not source.startswith("/data/"):
            continue
        out.append(
            {"path": target, "source": source, "note": "kept across system updates"}
        )
    return out, ""


def _size(path: str) -> str:
    total = 0
    for d, _, files in os.walk(path):
        for n in files:
            try:
                total += os.lstat(os.path.join(d, n)).st_size
            except OSError:
                pass
    return "%d KB" % (total // 1024) if total >= 1024 else "%d B" % total


def _data_dirs() -> tuple[list[dict], str]:
    try:
        names = sorted(os.listdir(DATA_DIR))
    except OSError as e:
        return [], str(e)
    out = []
    for n in names:
        p = os.path.join(DATA_DIR, n)
        if os.path.isdir(p):
            out.append({"path": p, "size": _size(p) if DATA_SIZE else ""})
    return out, ""


def persistence() -> dict:
    mounts, err1 = _mounts()
    data, err2 = _data_dirs()
    return {
        "mounts": mounts,
        "data": data,
        "error": " ".join(x for x in (err1, err2) if x),
    }


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else ""
    args = argv[2:]
    try:
        if cmd == "graphics":
            out = graphics()
        elif cmd == "etc-list":
            out = etc_list()
        elif cmd == "etc-diff" and len(args) == 1:
            out = etc_diff(args[0])
        elif cmd in ("etc-restore", "etc-cancel") and len(args) == 1:
            out = etc_queue(cmd.split("-")[1], args[0])
        elif cmd == "persistence":
            out = persistence()
        else:
            print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
            return 2
    except (OSError, subprocess.TimeoutExpired) as e:
        out = {"error": str(e)}
    print(json.dumps(out))
    return 1 if isinstance(out, dict) and out.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
