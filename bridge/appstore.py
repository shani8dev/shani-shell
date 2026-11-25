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
    appstore.py skipped                     [app ids held back with "Skip this version"]
    appstore.py skip <id> on|off            hold back / resume an app's updates
    appstore.py catalogue                   {"refreshed": <date>, "ageDays": <int>}: AppStream age
    appstore.py leftovers                   [{"id", "path", "size"}]: ~/.var/app folders of apps no
                                            longer installed (Warehouse's "Leftover data")
    appstore.py leftover-remove <id>        that folder to the trash
    appstore.py appimages                   [{"path", "name", "added"}]: ~/Applications' AppImages
    appstore.py appimage-add <file>         into ~/Applications, executable, with a launcher entry
                                            and icon taken from inside it (Gear Lever's job)
    appstore.py appimage-remove <file>      its launcher entry and icon gone, the file to the trash

ShaniOS's other ways in (docs/software in shani-docs), each as the docs do it:

    appstore.py nix-tools                   [{"name", "attr", "cmd", "about", "installed", "nix"}]:
                                            the everyday command-line tools; "nix" when Nix put it there
    appstore.py nix-install|nix-remove <attr>   nix-env -iA nixpkgs.<attr> (adding the nixpkgs channel
                                            the first time) / nix-env -e, per user, no password
    appstore.py snap-search <words>         [{"name", "version", "publisher", "summary", "classic"}]
    appstore.py snap-installed              [{"name", "version", "publisher", "classic", "update"}]
    appstore.py snap-install <name> [classic] | snap-remove <name> | snap-refresh [<name>]
    appstore.py nix-upgrade                 the channel updated, then nix-env -u '*'
                                            snapd asks the password through the shell's polkit agent

The catalogue is Flathub's AppStream file, which flatpak keeps; an index of it is
kept in ~/.cache/shani-shell/appstore-index.json until the file changes.
SHANI_FLATPAK (tests): the flatpak to run; SHANI_APPSTREAM: the catalogue file;
SHANI_SNAP, SHANI_NIX_ENV, SHANI_NIX_CHANNEL: the snap, nix-env and nix-channel to run.
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
SNAP = shlex.split(os.environ.get("SHANI_SNAP", "snap"))
NIX_ENV = shlex.split(os.environ.get("SHANI_NIX_ENV", "nix-env"))
NIX_CHANNEL = shlex.split(os.environ.get("SHANI_NIX_CHANNEL", "nix-channel"))
HOME = os.path.expanduser("~")
CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"),
    "shani-shell",
    "appstore-index.json",
)
SKIPPED = os.path.join(os.path.dirname(CACHE), "appstore-skipped.json")
APPDIR = os.path.join(HOME, "Applications")
DESKTOP_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share"),
    "applications",
)
ICON_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share"),
    "icons",
    "hicolor",
    "256x256",
    "apps",
)


def _run(*args, **kw):
    return subprocess.run(FLATPAK + list(args), capture_output=True, text=True, **kw)


# ---- the catalogue -----------------------------------------------------------------
def appstream_file() -> str:
    if os.environ.get("SHANI_APPSTREAM"):
        return os.environ["SHANI_APPSTREAM"]
    arch = os.uname().machine
    for base in ("/var/lib/flatpak", os.path.join(HOME, ".local/share/flatpak")):
        for name in ("appstream.xml.gz", "appstream.xml"):
            for p in glob.glob(
                os.path.join(base, "appstream", "flathub", arch, "active", name)
            ):
                return p
    return ""


def _text(el) -> str:
    """An AppStream description: its paragraphs and list items, as plain text."""
    if el is None:
        return ""
    out = []
    for child in el:
        if child.tag == "p" and not child.attrib.get(
            "{http://www.w3.org/XML/1998/namespace}lang"
        ):
            out.append(" ".join("".join(child.itertext()).split()))
        elif child.tag in ("ul", "ol"):
            out += [
                "• " + " ".join("".join(li.itertext()).split())
                for li in child
                if li.tag == "li"
                and not li.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")
            ]
    return "\n".join(x for x in out if x)


def build_index(path: str) -> list[dict]:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as f:
        root = ET.parse(f).getroot()
    icons = os.path.join(os.path.dirname(path), "icons", "128x128")
    apps = []
    for c in root.iter("component"):
        ctype = c.attrib.get("type")
        addon = ctype == "addon"
        if not addon and ctype not in (
            "desktop",
            "desktop-application",
            "console-application",
        ):
            continue
        cid = (c.findtext("id") or "").removesuffix(".desktop")
        name = (
            next(
                (
                    n.text
                    for n in c.findall("name")
                    if not n.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")
                ),
                "",
            )
            or cid
        )
        summary = (
            next(
                (
                    n.text
                    for n in c.findall("summary")
                    if not n.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")
                ),
                "",
            )
            or ""
        )
        shots = []
        for s in c.iter("screenshot"):
            img = next(
                (
                    i.text
                    for i in s.findall("image")
                    if i.attrib.get("type") == "source"
                ),
                None,
            ) or s.findtext("image")
            if img:
                shots.append(img.strip())
        icon = os.path.join(icons, cid + ".png")
        dev = c.find("developer")
        # version history: AppStream <release> nodes (version, timestamp, notes)
        releases = []
        for rel in c.findall("release"):
            releases.append(
                {
                    "version": rel.get("version") or "",
                    "timestamp": rel.get("timestamp") or rel.get("date") or "",
                    "notes": _text(rel.find("description")),
                }
            )
        releases.sort(key=lambda r: r["timestamp"], reverse=True)
        apps.append(
            {
                "id": cid,
                "name": name.strip(),
                "summary": summary.strip(),
                "description": _text(c.find("description")),
                "developer": (
                    dev.findtext("name")
                    if dev is not None
                    else c.findtext("developer_name")
                )
                or "",
                "license": c.findtext("project_license") or "",
                "homepage": next(
                    (
                        u.text
                        for u in c.findall("url")
                        if u.attrib.get("type") == "homepage"
                    ),
                    "",
                )
                or "",
                "categories": [x.text for x in c.iter("category") if x.text],
                "keywords": [
                    x.text
                    for x in c.iter("keyword")
                    if x.text
                    and not x.attrib.get("{http://www.w3.org/XML/1998/namespace}lang")
                ],
                "screenshots": shots[:4],
                "icon": icon if os.path.exists(icon) else "",
                "releases": releases[:8],
                "type": "addon" if addon else "app",
                "extends": (c.findtext("extends") or "").strip() if addon else "",
            }
        )
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


def catalogue() -> dict:
    import datetime

    path = appstream_file()
    if not path or not os.path.exists(path):
        return {"refreshed": "", "ageDays": None}
    day = datetime.datetime.fromtimestamp(os.path.getmtime(path)).date()
    return {"refreshed": day.isoformat(), "ageDays": (datetime.date.today() - day).days}


# apps held back by "Skip this version": a tiny state file beside the index
def skipped() -> set:
    try:
        with open(SKIPPED, encoding="utf-8") as f:
            return {x for x in json.load(f) if isinstance(x, str)}
    except (OSError, ValueError):
        return set()


def skip(app_id: str, on: bool) -> list:
    ids = skipped()
    if on:
        ids.add(app_id)
    else:
        ids.discard(app_id)
    os.makedirs(os.path.dirname(SKIPPED), exist_ok=True)
    tmp = SKIPPED + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(sorted(ids), f)
    os.replace(tmp, SKIPPED)
    return sorted(ids)


def _installed_ids() -> set:
    return {
        l.strip()
        for l in _run("list", "--app", "--columns=application").stdout.splitlines()
        if l.strip()
    }


def _brief(a, have):
    return {
        "id": a["id"],
        "name": a["name"],
        "summary": a["summary"],
        "icon": a["icon"],
        "installed": a["id"] in have,
    }


# ---- ODRS ratings / reviews -------------------------------------------------------
# GNOME's Open Desktop Ratings Service. SHANI_ODRS points at a local JSON file
# in tests (a list of {"rating": 1..5, "summary", "review"}); otherwise the
# public API is read with a short timeout and any failure is an honest zero.
ODRS_URL = "https://odrs.gnome.org/1.0/reviews/api/reviews/"


def odrs(app_id: str) -> list[dict]:
    src = os.environ.get("SHANI_ODRS", "")
    data = None
    if src and os.path.isfile(src):
        try:
            with open(src, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = None
    elif not src:
        try:
            import urllib.parse
            import urllib.request

            with urllib.request.urlopen(
                ODRS_URL + urllib.parse.quote(app_id, safe=""), timeout=3
            ) as r:
                data = json.loads(r.read().decode("utf-8", "replace"))
        except Exception:
            data = None
    return [x for x in data if isinstance(x, dict)] if isinstance(data, list) else []


def rating(app_id: str) -> dict:
    reviews = odrs(app_id)
    stars = [
        x.get("rating") for x in reviews if isinstance(x.get("rating"), (int, float))
    ]
    return {
        "rating": round(sum(stars) / len(stars), 1) if stars else 0,
        "ratingCount": len(stars),
        "reviews": [
            {
                "summary": str(x.get("summary") or "")[:120],
                "review": str(x.get("review") or "")[:400],
                "rating": x.get("rating"),
            }
            for x in reviews[:5]
        ],
    }


FEATURED_IDS = [
    "org.gimp.GIMP",
    "org.libreoffice.LibreOffice",
    "org.videolan.VLC",
    "com.spotify.Client",
    "org.mozilla.firefox",
    "org.audacityteam.Audacity",
    "com.google.Chrome",
    "org.blender.Blender",
]


def featured() -> list[dict]:
    apps = [a for a in index() if a.get("type") != "addon"]
    have = _installed_ids()
    picks = [a for fid in FEATURED_IDS for a in apps if a["id"] == fid]
    if len(picks) < 4:
        picks += sorted(apps, key=lambda a: a["name"].lower())[: 8 - len(picks)]
    return [_brief(a, have) for a in picks[:8]]


def addons(app_id: str) -> list[dict]:
    have = _installed_ids()
    return [
        {
            "id": a["id"],
            "name": a["name"],
            "summary": a["summary"],
            "installed": a["id"] in have,
        }
        for a in index()
        if a.get("type") == "addon" and a.get("extends") == app_id
    ]


def remotes() -> list[dict]:
    r = _run(
        "remote-list",
        "--columns=name,url,disabled",
    )
    if r.returncode != 0:
        return []
    out = []
    for line in r.stdout.splitlines():
        f = line.split("\t")
        if len(f) >= 2 and f[0].strip():
            out.append(
                {
                    "name": f[0].strip(),
                    "url": f[1].strip(),
                    "disabled": (f[2].strip() if len(f) > 2 else "")
                    in ("yes", "true", "1"),
                }
            )
    return out


def search(words: str, category: str = "") -> list[dict]:
    have = _installed_ids()
    ws = [w for w in words.lower().split() if w]
    scored = []
    for a in index():
        if a.get("type") == "addon":  # extensions are shown on their app's page
            continue
        if category and category not in a["categories"]:
            continue
        if not ws:
            scored.append((0, a))
            continue
        name, summ = a["name"].lower(), a["summary"].lower()
        rest = (
            a["description"] + " " + " ".join(a["keywords"]) + " " + a["id"]
        ).lower()
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
        return {
            "id": app_id,
            "name": app_id,
            "summary": "",
            "description": "",
            "installed": app_id in have,
        }
    # how old the latest release is, so the UI can warn about unmaintained apps
    age = None
    rels = a.get("releases") or []
    if rels and rels[0].get("timestamp"):
        try:
            import datetime

            ts = int(rels[0]["timestamp"][:10])
            age = (datetime.date.today() - datetime.date.fromtimestamp(ts)).days
        except (ValueError, OverflowError, OSError):
            age = None
    out = dict(a, installed=app_id in have, ageDays=age)
    out.update(rating(app_id))
    out["addons"] = addons(app_id)
    return out


def installed() -> list[dict]:
    r = _run(
        "list", "--app", "--columns=application,name,version,origin,installation,size"
    )
    held = skipped()
    ups = {
        l.split("\t")[0].strip()
        for l in _run(
            "remote-ls", "--updates", "--app", "--columns=application"
        ).stdout.splitlines()
        if l.strip() and l.split("\t")[0].strip() not in held
    }
    icons = {a["id"]: a["icon"] for a in index()}
    out = []
    for line in r.stdout.splitlines():
        f = line.split("\t")
        if len(f) < 6:
            continue
        out.append(
            {
                "id": f[0],
                "name": f[1] or f[0],
                "version": f[2],
                "origin": f[3],
                "installation": f[4],
                "size": f[5],
                "update": f[0] in ups,
                "icon": icons.get(f[0], ""),
            }
        )
    return sorted(out, key=lambda a: a["name"].lower())


# ---- install, remove, update: flatpak's own output, read as it goes ---------------------
PCT = re.compile(r"(\d{1,3})%")


def stream(args: list[str], tool: list[str] | None = None) -> int:
    p = subprocess.Popen(
        (FLATPAK if tool is None else tool) + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    last = ""
    for raw in p.stdout:
        for line in raw.replace("\r", "\n").splitlines():
            line = line.strip()
            if not line:
                continue
            last = line
            m = PCT.findall(line)
            print(
                json.dumps({"progress": int(m[-1]) if m else None, "line": line[:200]}),
                flush=True,
            )
    rc = p.wait()
    print(
        json.dumps({"ok": True} if rc == 0 else {"error": last or "%s failed" % ((tool or FLATPAK)[0])}),
        flush=True,
    )
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
    return [
        {"id": n, "path": os.path.join(base, n), "size": _du(os.path.join(base, n))}
        for n in sorted(os.listdir(base))
        if n not in have and os.path.isdir(os.path.join(base, n))
    ]


def _trash(path: str) -> dict:
    r = subprocess.run(["gio", "trash", "--", path], capture_output=True, text=True)
    return (
        {"ok": True}
        if r.returncode == 0
        else {
            "error": (r.stderr.strip().splitlines() or ["not moved to the trash"])[-1]
        }
    )


# ---- AppImages (Gear Lever) ----------------------------------------------------------------
def _desktop_for(path: str) -> str:
    return os.path.join(
        DESKTOP_DIR,
        "appimage-"
        + re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(path))
        + ".desktop",
    )


def appimages() -> list[dict]:
    if not os.path.isdir(APPDIR):
        return []
    return [
        {
            "path": p,
            "name": os.path.basename(p).rsplit(".", 1)[0],
            "added": os.path.exists(_desktop_for(p)),
        }
        for p in sorted(
            glob.glob(os.path.join(APPDIR, "*.AppImage"))
            + glob.glob(os.path.join(APPDIR, "*.appimage"))
        )
    ]


def appimage_add(src: str) -> dict:
    src = os.path.abspath(src)
    if not os.path.isfile(src):
        return {"error": "not a file"}
    os.makedirs(APPDIR, exist_ok=True)
    dst = (
        src
        if os.path.dirname(src) == APPDIR
        else os.path.join(APPDIR, os.path.basename(src))
    )
    if dst != src:
        if os.path.lexists(dst):
            return {"error": "%s is in Applications already" % os.path.basename(dst)}
        shutil.move(src, dst)
    os.chmod(dst, os.stat(dst).st_mode | 0o111)
    # its own .desktop and icon, from inside it (the AppImage's --appimage-extract)
    import tempfile

    name, icon_file, comment, cats = (
        os.path.basename(dst).rsplit(".", 1)[0],
        "",
        "",
        "Utility;",
    )
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            [dst, "--appimage-extract", "*.desktop"],
            cwd=tmp,
            capture_output=True,
            timeout=60,
        )
        subprocess.run(
            [dst, "--appimage-extract", ".DirIcon"],
            cwd=tmp,
            capture_output=True,
            timeout=60,
        )
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
            icon_file = os.path.join(
                ICON_DIR,
                "appimage-"
                + re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(dst))
                + ".png",
            )
            shutil.copyfile(os.path.realpath(di), icon_file)
    os.makedirs(DESKTOP_DIR, exist_ok=True)
    with open(_desktop_for(dst), "w", encoding="utf-8") as f:
        f.write(
            '[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec="%s" %%U\nIcon=%s\nCategories=%s\nX-Shani-AppImage=%s\n'
            % (name, comment, dst, icon_file or "application-x-executable", cats, dst)
        )
    return {"ok": True, "path": dst, "name": name}


def appimage_remove(path: str) -> dict:
    path = os.path.abspath(path)
    d = _desktop_for(path)
    for p in (
        d,
        os.path.join(
            ICON_DIR,
            "appimage-"
            + re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(path))
            + ".png",
        ),
    ):
        if os.path.lexists(p):
            os.remove(p)  # what appimage-add made
    return _trash(path) if os.path.exists(path) else {"ok": True}


# ---- Nix: the command-line tools (shani-docs software/nix.md, development.md) ----
# Per user, in ~/.nix-profile on the @nix subvolume: kept across OS updates and
# rollbacks, no password. Docker is not here: it needs a system service, and
# rootless Podman (the Containers app) is ShaniOS's container engine.
NIX_TOOLS = [
    ("git", "git", "git", "version control"),
    ("Node.js", "nodejs", "node", "JavaScript runtime"),
    ("Python", "python3", "python3", "Python 3"),
    ("uv", "uv", "uv", "fast Python packages and virtualenvs"),
    ("Go", "go", "go", "the Go toolchain"),
    ("rustup", "rustup", "rustup", "the Rust toolchain installer"),
    ("mise", "mise", "mise", "per-project tool versions"),
    ("Neovim", "neovim", "nvim", "editor"),
    ("ripgrep", "ripgrep", "rg", "search file contents"),
    ("fd", "fd", "fd", "find files"),
    ("jq", "jq", "jq", "JSON on the command line"),
    ("GitHub CLI", "gh", "gh", "pull requests and issues"),
    ("lazygit", "lazygit", "lazygit", "git in the terminal"),
]
NIX_ATTR = re.compile(r"^[A-Za-z0-9_.+-]+$")


def _nix_names() -> set:
    """pnames of what nix-env put in this user's profile."""
    try:
        r = subprocess.run(NIX_ENV + ["-q", "--json"], capture_output=True, text=True, timeout=60)
        return {v.get("pname", "") for v in json.loads(r.stdout or "{}").values()}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return set()


def nix_tools() -> list[dict]:
    have = shutil.which(NIX_ENV[0]) is not None
    mine = _nix_names() if have else set()
    prof = os.path.join(HOME, ".nix-profile", "bin")
    out = []
    for name, attr, cmd, about in NIX_TOOLS:
        nix = attr in mine or cmd in mine
        out.append({"name": name, "attr": attr, "cmd": cmd, "about": about, "nix": nix,
                    "installed": nix or shutil.which(cmd) is not None or os.access(os.path.join(prof, cmd), os.X_OK)})
    return out


def nix_install(attr: str) -> int:
    # the docs' first-time setup: the nixpkgs channel, once
    chans = subprocess.run(NIX_CHANNEL + ["--list"], capture_output=True, text=True, timeout=30).stdout
    if not any(l.split()[:1] == ["nixpkgs"] for l in chans.splitlines()):
        print(json.dumps({"progress": None, "line": "Adding the nixpkgs channel (once)"}), flush=True)
        if subprocess.run(NIX_CHANNEL + ["--add", "https://nixos.org/channels/nixpkgs-unstable", "nixpkgs"],
                          capture_output=True, text=True, timeout=60).returncode != 0:
            print(json.dumps({"error": "could not add the nixpkgs channel"}), flush=True)
            return 1
        print(json.dumps({"progress": None, "line": "Fetching the package list (the first time takes a while)"}), flush=True)
        if stream(["--update"], NIX_CHANNEL) != 0:
            return 1
    return stream(["-iA", "nixpkgs." + attr], NIX_ENV)


# ---- Snap (shani-docs software/snaps.md): snapd is socket-activated ----------
def _snap_table(args: list[str]) -> list[list[str]]:
    r = subprocess.run(SNAP + args, capture_output=True, text=True, timeout=60)
    rows = [re.split(r"\s{2,}", l.strip()) for l in r.stdout.splitlines() if l.strip()]
    return rows[1:] if rows and rows[0] and rows[0][0] == "Name" else []


def _publisher(p: str) -> str:
    return re.sub(r"[*✓✪]+$", "", p).strip()


def snap_search(words: str) -> list[dict]:
    out = []
    for row in _snap_table(["find", words]):
        if len(row) < 5:
            continue
        name, version, pub, notes, summary = row[0], row[1], row[2], row[3], " ".join(row[4:])
        out.append({"name": name, "version": version, "publisher": _publisher(pub),
                    "summary": summary, "classic": "classic" in notes})
    return out


def snap_installed() -> list[dict]:
    updates = {r[0] for r in _snap_table(["refresh", "--list"]) if r}
    out = []
    for row in _snap_table(["list"]):
        if len(row) < 6:
            row = row + [""] * (6 - len(row))
        name, version, _rev, _track, pub, notes = row[:6]
        # the snaps snapd runs on are not apps to manage here
        if any(n in notes.split(",") for n in ("base", "core", "snapd")) or name in ("snapd", "bare"):
            continue
        out.append({"name": name, "version": version, "publisher": _publisher(pub),
                    "classic": "classic" in notes, "update": name in updates})
    return out


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    try:
        if cmd == "refresh":
            r = _run("update", "--appstream", "--noninteractive", timeout=300)
            out = (
                {"ok": True}
                if r.returncode == 0
                else {"error": (r.stderr.strip().splitlines() or ["not refreshed"])[-1]}
            )
        elif cmd == "search" and args:
            out = search(args[0], args[1] if len(args) > 1 else "")
        elif cmd == "category" and len(args) == 1:
            out = search("", args[0])
        elif cmd == "info" and len(args) == 1:
            out = info(args[0])
        elif cmd == "featured":
            out = featured()
        elif cmd == "reviews" and len(args) == 1:
            out = rating(args[0])["reviews"]
        elif cmd == "addons" and len(args) == 1:
            out = addons(args[0])
        elif cmd == "remotes":
            out = remotes()
        elif cmd == "remote-toggle" and len(args) == 2 and args[1] in ("on", "off"):
            r = _run(
                "remote-modify",
                "--enable" if args[1] == "on" else "--disable",
                args[0],
            )
            out = {"ok": r.returncode == 0, "error": r.stderr.strip() or None}
            out = {k: v for k, v in out.items() if v is not None}
        elif cmd == "installed":
            out = installed()
        elif cmd in ("install", "remove", "update") and len(args) == 1:
            if not _safe_id(args[0]):
                out = {"error": "not an app id: %s" % args[0]}
            else:
                verb = {
                    "install": ["install", "-y", "--noninteractive", "flathub"],
                    "remove": ["uninstall", "-y", "--noninteractive"],
                    "update": ["update", "-y", "--noninteractive"],
                }[cmd]
                return 0 if stream(verb + [args[0]]) == 0 else 1
        elif cmd == "install-ref" and len(args) == 1:
            if not os.path.isfile(args[0]) or not args[0].endswith(
                (".flatpakref", ".flatpakrepo")
            ):
                out = {"error": "not a .flatpakref file"}
            else:
                verb = (
                    ["remote-add", "--if-not-exists", "--from"]
                    if args[0].endswith(".flatpakrepo")
                    else ["install", "-y", "--noninteractive", "--from"]
                )
                if verb[0] == "remote-add":
                    name = os.path.basename(args[0]).rsplit(".", 1)[0]
                    return 0 if stream(verb + [name, args[0]]) == 0 else 1
                return 0 if stream(verb + [args[0]]) == 0 else 1
        elif cmd == "update-all":
            # only the unheld apps: flatpak's "update everything" has no exclude
            held = skipped()
            ids = sorted(
                l.split("\t")[0].strip()
                for l in _run(
                    "remote-ls", "--updates", "--app", "--columns=application"
                ).stdout.splitlines()
                if l.strip() and l.split("\t")[0].strip() not in held
            )
            if not ids:
                print(json.dumps({"ok": True}))
                return 0
            return 0 if stream(["update", "-y", "--noninteractive"] + ids) == 0 else 1
        elif cmd == "skipped":
            out = sorted(skipped())
        elif (
            cmd == "skip"
            and len(args) == 2
            and _safe_id(args[0])
            and args[1] in ("on", "off")
        ):
            out = skip(args[0], args[1] == "on")
        elif cmd == "catalogue":
            out = catalogue()
        elif cmd == "leftovers":
            out = leftovers()
        elif cmd == "leftover-remove" and len(args) == 1:
            p = os.path.join(HOME, ".var", "app", os.path.basename(args[0]))
            out = (
                _trash(p)
                if _safe_id(args[0])
                and os.path.isdir(p)
                and args[0] not in _installed_ids()
                else {"error": "not a leftover"}
            )
        elif cmd == "nix-tools":
            out = nix_tools()
        elif cmd in ("nix-install", "nix-remove") and len(args) == 1:
            if not NIX_ATTR.match(args[0]):
                out = {"error": "not a package name: %s" % args[0]}
            elif cmd == "nix-install":
                return 0 if nix_install(args[0]) == 0 else 1
            else:
                return 0 if stream(["-e", args[0]], NIX_ENV) == 0 else 1
        elif cmd == "snap-search" and len(args) == 1:
            out = snap_search(args[0])
        elif cmd == "snap-installed":
            out = snap_installed()
        elif cmd in ("snap-install", "snap-remove") and args and NIX_ATTR.match(args[0]):
            verb = ["install", args[0]] + (["--classic"] if args[1:] == ["classic"] else []) \
                if cmd == "snap-install" else ["remove", args[0]]
            return 0 if stream(verb, SNAP) == 0 else 1
        elif cmd == "snap-refresh" and (not args or NIX_ATTR.match(args[0])):
            return 0 if stream(["refresh"] + args[:1], SNAP) == 0 else 1
        elif cmd == "nix-upgrade":
            # the docs' "upgrade all": the channel, then every package in the profile
            if stream(["--update"], NIX_CHANNEL) != 0:
                return 1
            return 0 if stream(["-u", "*"], NIX_ENV) == 0 else 1
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
