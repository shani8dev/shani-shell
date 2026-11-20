#!/usr/bin/env python3
"""appstore — the shell's Software window (GNOME Software, Warehouse and Gear
Lever's jobs), through the `flatpak` command and Flathub's own catalogue.

    appstore.py refresh                     the catalogue fetched again (flatpak update --appstream)
    appstore.py search <words> [category]   [{"id", "name", "summary", "icon", "installed"}] best first
    appstore.py category <name>             the same, for AudioVideo, Development, Game, Graphics ...
    appstore.py info <id>                   {"id", "name", "summary", "description", "developer",
                                             "license", "homepage", "screenshots", "icon", "installed"}
    appstore.py installed                   [{"id", "name", "version", "origin", "installation", "size",
                                             "update"}]
    appstore.py install|remove|update <id>  prints {"progress": 0..100, "line"} as it goes, then {"ok"}
    appstore.py install-ref <file>          a .flatpakref (a website's "Install" link), with progress
    appstore.py update-all
    appstore.py leftovers                   [{"id", "path", "size"}]: ~/.var/app folders of apps no
                                            longer installed (Warehouse's "Leftover data")
    appstore.py leftover-remove <id>        that folder to the trash
    appstore.py appimages                   [{"path", "name", "added"}]: ~/Applications' AppImages
    appstore.py appimage-add <file>         into ~/Applications, executable, with a launcher entry
                                            and icon taken from inside it (Gear Lever's job)
    appstore.py appimage-remove <file>      its launcher entry and icon gone, the file to the trash

The catalogue is Flathub's AppStream file, which flatpak keeps; an index of it is
kept in ~/.cache/shani-shell/appstore-index.json until the file changes.
SHANI_FLATPAK (tests): the flatpak to run; SHANI_APPSTREAM: the catalogue file.
"""
from __future__ import annotations

import glob
import gzip
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

FLATPAK = shlex.split(os.environ.get("SHANI_FLATPAK", "flatpak"))
HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "shani-shell", "appstore-index.json")
APPDIR = os.path.join(HOME, "Applications")
DESKTOP_DIR = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share"), "applications")
ICON_DIR = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share"), "icons", "hicolor", "256x256", "apps")


def _run(*args, **kw):
    return subprocess.run(FLATPAK + list(args), capture_output=True, text=True, **kw)


# ---- the catalogue -----------------------------------------------------------------
def appstream_file() -> str:
    if os.environ.get("SHANI_APPSTREAM"):
        return os.environ["SHANI_APPSTREAM"]
    arch = os.uname().machine
    for base in ("/var/lib/flatpak", os.path.join(HOME, ".local/share/flatpak")):
        for name in ("appstream.xml.gz", "appstream.xml"):
            for p in glob.glob(os.path.join(base, "appstream", "flathub", arch, "active", name)):
                return p
    return ""


def _text(el) -> str:
    """An AppStream description: its paragraphs and list items, as plain text."""
    if el is None:
        return ""
    out = []
    for child in el:
        if child.tag == "p" and not child.attrib.get("{http://www.w3.org/XML/1998/namespace}lang"):
            out.append(" ".join("".join(child.itertext()).split()))
        elif child.tag in ("ul", "ol"):
            out += ["• " + " ".join("".join(li.itertext()).split()) for li in child if li.tag == "li" and not li.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")]
    return "\n".join(x for x in out if x)


def build_index(path: str) -> list[dict]:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as f:
        root = ET.parse(f).getroot()
    icons = os.path.join(os.path.dirname(path), "icons", "128x128")
    apps = []
    for c in root.iter("component"):
        if c.attrib.get("type") not in ("desktop", "desktop-application", "console-application"):
            continue
        cid = (c.findtext("id") or "").removesuffix(".desktop")
        name = next((n.text for n in c.findall("name") if not n.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")), "") or cid
        summary = next((n.text for n in c.findall("summary") if not n.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")), "") or ""
        shots = []
        for s in c.iter("screenshot"):
            img = next((i.text for i in s.findall("image") if i.attrib.get("type") == "source"), None) or s.findtext("image")
            if img:
                shots.append(img.strip())
        icon = os.path.join(icons, cid + ".png")
        dev = c.find("developer")
        apps.append({"id": cid, "name": name.strip(), "summary": summary.strip(), "description": _text(c.find("description")),
                     "developer": (dev.findtext("name") if dev is not None else c.findtext("developer_name")) or "",
                     "license": c.findtext("project_license") or "",
                     "homepage": next((u.text for u in c.findall("url") if u.attrib.get("type") == "homepage"), "") or "",
                     "categories": [x.text for x in c.iter("category") if x.text],
                     "keywords": [x.text for x in c.iter("keyword") if x.text and not x.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")],
                     "screenshots": shots[:4], "icon": icon if os.path.exists(icon) else ""})
    return apps


def index() -> list[dict]:
    path = appstream_file()
    if not path:
        return []
    mtime = os.path.getmtime(path)
    try:
        with open(CACHE, encoding="utf-8") as f:
            cached = json.load(f)
        if cached.get("source") == path and cached.get("mtime") == mtime:
            return cached["apps"]
    except (OSError, ValueError):
        pass
    apps = build_index(path)
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"source": path, "mtime": mtime, "apps": apps}, f)
    os.replace(tmp, CACHE)
    return apps


def _installed_ids() -> set:
    return {l.strip() for l in _run("list", "--app", "--columns=application").stdout.splitlines() if l.strip()}


def _brief(a, have):
    return {"id": a["id"], "name": a["name"], "summary": a["summary"], "icon": a["icon"], "installed": a["id"] in have}


def search(words: str, category: str = "") -> list[dict]:
    have = _installed_ids()
    ws = [w for w in words.lower().split() if w]
    scored = []
    for a in index():
        if category and category not in a["categories"]:
            continue
        if not ws:
            scored.append((0, a))
            continue
        name, summ = a["name"].lower(), a["summary"].lower()
        rest = (a["description"] + " " + " ".join(a["keywords"]) + " " + a["id"]).lower()
        score = 0
        for w in ws:
            if name == w:
                score += 100
            elif name.startswith(w):
                score += 60
            elif w in name:
                score += 40
            elif w in summ:
                score += 15
            elif w in rest:
                score += 5
            else:
                score = -1
                break
        if score > 0:
            scored.append((score, a))
    scored.sort(key=lambda x: (-x[0], x[1]["name"].lower()))
    return [_brief(a, have) for _, a in scored[:120]]


def info(app_id: str) -> dict:
    a = next((x for x in index() if x["id"] == app_id), None)
    have = _installed_ids()
    if not a:
        return {"id": app_id, "name": app_id, "summary": "", "description": "", "installed": app_id in have}
    return dict(a, installed=app_id in have)


def installed() -> list[dict]:
    r = _run("list", "--app", "--columns=application,name,version,origin,installation,size")
    ups = {l.split("\t")[0].strip() for l in _run("remote-ls", "--updates", "--app", "--columns=application").stdout.splitlines() if l.strip()}
    icons = {a["id"]: a["icon"] for a in index()}
    out = []
    for line in r.stdout.splitlines():
        f = line.split("\t")
        if len(f) < 6:
            continue
        out.append({"id": f[0], "name": f[1] or f[0], "version": f[2], "origin": f[3], "installation": f[4], "size": f[5],
                    "update": f[0] in ups, "icon": icons.get(f[0], "")})
    return sorted(out, key=lambda a: a["name"].lower())


# ---- install, remove, update: flatpak's own output, read as it goes ---------------------
PCT = re.compile(r"(\d{1,3})%")


def stream(args: list[str]) -> int:
    p = subprocess.Popen(FLATPAK + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    last = ""
    for raw in p.stdout:
        for line in raw.replace("\r", "\n").splitlines():
            line = line.strip()
            if not line:
                continue
            last = line
            m = PCT.findall(line)
            print(json.dumps({"progress": int(m[-1]) if m else None, "line": line[:200]}), flush=True)
    rc = p.wait()
    print(json.dumps({"ok": True} if rc == 0 else {"error": last or "flatpak failed"}), flush=True)
    return rc


def _safe_id(app_id: str) -> bool:
    return bool(re.match(r"^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$", app_id or ""))


# ---- leftovers (Warehouse) --------------------------------------------------------------
def _du(path: str) -> int:
    total = 0
    for d, _, files in os.walk(path):
        for n in files:
            try:
                total += os.lstat(os.path.join(d, n)).st_size
            except OSError:
                pass
    return total


def leftovers() -> list[dict]:
    base = os.path.join(HOME, ".var", "app")
    if not os.path.isdir(base):
        return []
    have = _installed_ids()
    return [{"id": n, "path": os.path.join(base, n), "size": _du(os.path.join(base, n))}
            for n in sorted(os.listdir(base)) if n not in have and os.path.isdir(os.path.join(base, n))]


def _trash(path: str) -> dict:
    r = subprocess.run(["gio", "trash", "--", path], capture_output=True, text=True)
    return {"ok": True} if r.returncode == 0 else {"error": (r.stderr.strip().splitlines() or ["not moved to the trash"])[-1]}


# ---- AppImages (Gear Lever) ----------------------------------------------------------------
def _desktop_for(path: str) -> str:
    return os.path.join(DESKTOP_DIR, "appimage-" + re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(path)) + ".desktop")


def appimages() -> list[dict]:
    if not os.path.isdir(APPDIR):
        return []
    return [{"path": p, "name": os.path.basename(p).rsplit(".", 1)[0], "added": os.path.exists(_desktop_for(p))}
            for p in sorted(glob.glob(os.path.join(APPDIR, "*.AppImage")) + glob.glob(os.path.join(APPDIR, "*.appimage")))]


def appimage_add(src: str) -> dict:
    src = os.path.abspath(src)
    if not os.path.isfile(src):
        return {"error": "not a file"}
    os.makedirs(APPDIR, exist_ok=True)
    dst = src if os.path.dirname(src) == APPDIR else os.path.join(APPDIR, os.path.basename(src))
    if dst != src:
        if os.path.lexists(dst):
            return {"error": "%s is in Applications already" % os.path.basename(dst)}
        shutil.move(src, dst)
    os.chmod(dst, os.stat(dst).st_mode | 0o111)
    # its own .desktop and icon, from inside it (the AppImage's --appimage-extract)
    import tempfile
    name, icon_file, comment, cats = os.path.basename(dst).rsplit(".", 1)[0], "", "", "Utility;"
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([dst, "--appimage-extract", "*.desktop"], cwd=tmp, capture_output=True, timeout=60)
        subprocess.run([dst, "--appimage-extract", ".DirIcon"], cwd=tmp, capture_output=True, timeout=60)
        desk = glob.glob(os.path.join(tmp, "squashfs-root", "*.desktop"))
        if desk:
            for line in open(desk[0], encoding="utf-8", errors="replace"):
                k, _, v = line.strip().partition("=")
                if k == "Name" and v:
                    name = v
                elif k == "Comment" and v:
                    comment = v
                elif k == "Categories" and v:
                    cats = v
        di = os.path.join(tmp, "squashfs-root", ".DirIcon")
        if os.path.exists(di):
            os.makedirs(ICON_DIR, exist_ok=True)
            icon_file = os.path.join(ICON_DIR, "appimage-" + re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(dst)) + ".png")
            shutil.copyfile(os.path.realpath(di), icon_file)
    os.makedirs(DESKTOP_DIR, exist_ok=True)
    with open(_desktop_for(dst), "w", encoding="utf-8") as f:
        f.write("[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec=\"%s\" %%U\nIcon=%s\nCategories=%s\nX-Shani-AppImage=%s\n"
                % (name, comment, dst, icon_file or "application-x-executable", cats, dst))
    return {"ok": True, "path": dst, "name": name}


def appimage_remove(path: str) -> dict:
    path = os.path.abspath(path)
    d = _desktop_for(path)
    for p in (d, os.path.join(ICON_DIR, "appimage-" + re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(path)) + ".png")):
        if os.path.lexists(p):
            os.remove(p)                                  # what appimage-add made
    return _trash(path) if os.path.exists(path) else {"ok": True}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    try:
        if cmd == "refresh":
            r = _run("update", "--appstream", "--noninteractive", timeout=300)
            out = {"ok": True} if r.returncode == 0 else {"error": (r.stderr.strip().splitlines() or ["not refreshed"])[-1]}
        elif cmd == "search" and args:
            out = search(args[0], args[1] if len(args) > 1 else "")
        elif cmd == "category" and len(args) == 1:
            out = search("", args[0])
        elif cmd == "info" and len(args) == 1:
            out = info(args[0])
        elif cmd == "installed":
            out = installed()
        elif cmd in ("install", "remove", "update") and len(args) == 1:
            if not _safe_id(args[0]):
                out = {"error": "not an app id: %s" % args[0]}
            else:
                verb = {"install": ["install", "-y", "--noninteractive", "flathub"], "remove": ["uninstall", "-y", "--noninteractive"],
                        "update": ["update", "-y", "--noninteractive"]}[cmd]
                return 0 if stream(verb + [args[0]]) == 0 else 1
        elif cmd == "install-ref" and len(args) == 1:
            if not os.path.isfile(args[0]) or not args[0].endswith((".flatpakref", ".flatpakrepo")):
                out = {"error": "not a .flatpakref file"}
            else:
                verb = ["remote-add", "--if-not-exists", "--from"] if args[0].endswith(".flatpakrepo") else ["install", "-y", "--noninteractive", "--from"]
                if verb[0] == "remote-add":
                    name = os.path.basename(args[0]).rsplit(".", 1)[0]
                    return 0 if stream(verb + [name, args[0]]) == 0 else 1
                return 0 if stream(verb + [args[0]]) == 0 else 1
        elif cmd == "update-all":
            return 0 if stream(["update", "-y", "--noninteractive"]) == 0 else 1
        elif cmd == "leftovers":
            out = leftovers()
        elif cmd == "leftover-remove" and len(args) == 1:
            p = os.path.join(HOME, ".var", "app", os.path.basename(args[0]))
            out = _trash(p) if _safe_id(args[0]) and os.path.isdir(p) and args[0] not in _installed_ids() else {"error": "not a leftover"}
        elif cmd == "appimages":
            out = appimages()
        elif cmd == "appimage-add" and len(args) == 1:
            out = appimage_add(args[0])
        elif cmd == "appimage-remove" and len(args) == 1:
            out = appimage_remove(args[0])
        else:
            print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
            return 2
    except (OSError, ET.ParseError, subprocess.TimeoutExpired) as e:
        out = {"error": str(e)}
    print(json.dumps(out))
    return 1 if isinstance(out, dict) and "error" in out else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
