"""bridge/appstore.py: Flathub's catalogue read (and kept as an index), searched
best first, browsed by category; installed apps with their updates; install
progress read from flatpak's output; leftovers of removed apps; AppImages added
to the launcher and removed - against a stand-in flatpak and AppImage."""

import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BRIDGE = HERE.parent / "bridge" / "appstore.py"
FAKE = r"""#!/bin/sh
echo "$*" >> "$T/calls"
case "$1 $2" in
"list --app") case "$3" in --columns=application) printf 'org.example.Notes\n';; *) printf 'org.example.Notes\tNotes\t1.2\tflathub\tsystem\t12.0 MB\n';; esac ;;
"remote-ls --updates") printf 'org.example.Notes\n' ;;
"install -y") printf 'Installing 1/2\r 10%%\r 55%%\n Installing 2/2 100%%\n' ;;
"uninstall -y") echo "error: nope" >&2; exit 1 ;;
esac
"""


def run(tmp_path, *args):
    fake = tmp_path / "flatpak"
    if not fake.exists():
        fake.write_text(FAKE)
        fake.chmod(0o755)
    env = dict(
        os.environ,
        SHANI_FLATPAK=str(fake),
        T=str(tmp_path),
        HOME=str(tmp_path / "home"),
        XDG_CACHE_HOME=str(tmp_path / "cache"),
        XDG_DATA_HOME=str(tmp_path / "data"),
        SHANI_APPSTREAM=str(HERE / "fixtures" / "appstream.xml"),
    )
    (tmp_path / "home").mkdir(exist_ok=True)
    r = subprocess.run(
        [sys.executable, str(BRIDGE), *map(str, args)],
        capture_output=True,
        text=True,
        env=env,
    )
    lines = [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
    return (lines if len(lines) > 1 else lines[0] if lines else None), r.returncode


def test_catalogue_search_and_category(tmp_path):
    r, _ = run(tmp_path, "search", "notes")
    assert [a["id"] for a in r] == [
        "org.example.Notes",
        "org.example.Game",
    ]  # the name match first
    assert r[0]["installed"] is True and r[1]["installed"] is False
    assert [a["id"] for a in run(tmp_path, "search", "memo")[0]] == [
        "org.example.Notes"
    ]  # a keyword
    assert [a["id"] for a in run(tmp_path, "category", "Game")[0]] == [
        "org.example.Game"
    ]
    assert (tmp_path / "cache" / "shani-shell" / "appstore-index.json").exists()
    i, _ = run(tmp_path, "info", "org.example.Notes")
    assert (
        i["description"] == "A notes app.\n• Fast\n• Private"
        and i["developer"] == "Example Org"
    )
    assert (
        i["license"] == "GPL-3.0-or-later"
        and i["screenshots"] == ["https://example.org/s1.png"]
        and i["name"] == "Notes"
    )


def test_info_carries_addons_and_reviews_for_the_app_page(tmp_path):
    """The page has one read: the add-ons and reviews travel inside `info`."""
    i, _ = run(tmp_path, "info", "org.example.Notes")
    assert i["addons"] == [
        {
            "id": "org.example.Notes.Extra",
            "name": "Extra tools",
            "summary": "More tools for Notes",
            "installed": False,
        }
    ]
    assert i["ratingCount"] == 0  # no network in the unit run


def test_installed_with_updates(tmp_path):
    r, _ = run(tmp_path, "installed")
    assert r == [
        {
            "id": "org.example.Notes",
            "name": "Notes",
            "version": "1.2",
            "origin": "flathub",
            "installation": "system",
            "size": "12.0 MB",
            "update": True,
            "icon": "",
        }
    ]


def test_install_progress_and_errors(tmp_path):
    lines, rc = run(tmp_path, "install", "org.example.Game")
    assert (
        rc == 0
        and lines[-1] == {"ok": True}
        and [l["progress"] for l in lines[:-1] if l["progress"] is not None]
        == [10, 55, 100]
    )
    assert (
        "install -y --noninteractive flathub org.example.Game"
        in (tmp_path / "calls").read_text()
    )
    out, rc = run(tmp_path, "remove", "org.example.Notes")
    assert rc == 1 and out[-1] == {"error": "error: nope"}
    out, rc = run(tmp_path, "install", "; rm -rf ~")
    assert rc == 1 and "not an app id" in out["error"]


def test_leftovers(tmp_path):
    (tmp_path / "home" / ".var" / "app" / "org.gone.App" / "data").mkdir(parents=True)
    (tmp_path / "home" / ".var" / "app" / "org.gone.App" / "data" / "x").write_bytes(
        b"x" * 2048
    )
    (tmp_path / "home" / ".var" / "app" / "org.example.Notes").mkdir(parents=True)
    r, _ = run(tmp_path, "leftovers")
    assert r == [
        {
            "id": "org.gone.App",
            "path": str(tmp_path / "home" / ".var" / "app" / "org.gone.App"),
            "size": 2048,
        }
    ]
    assert run(tmp_path, "leftover-remove", "org.example.Notes")[0] == {
        "error": "not a leftover"
    }


def test_appimage_added_and_removed(tmp_path):
    img = tmp_path / "Tool-1.0.AppImage"
    img.write_text(
        '#!/bin/sh\nif [ "$1" = --appimage-extract ]; then mkdir -p squashfs-root; case "$2" in *desktop) printf "[Desktop Entry]\\nName=Tool\\nComment=A tool\\nCategories=Development;\\n" > squashfs-root/tool.desktop;; .DirIcon) printf PNG > squashfs-root/.DirIcon;; esac; fi\n'
    )
    r, rc = run(tmp_path, "appimage-add", img)
    dst = tmp_path / "home" / "Applications" / "Tool-1.0.AppImage"
    assert (
        rc == 0
        and r["name"] == "Tool"
        and dst.exists()
        and os.access(dst, os.X_OK)
        and not img.exists()
    )
    desk = (
        tmp_path / "data" / "applications" / "appimage-Tool-1.0.AppImage.desktop"
    ).read_text()
    assert (
        "Name=Tool" in desk
        and 'Exec="%s" %%U' % dst in desk
        and "Categories=Development;" in desk
    )
    assert run(tmp_path, "appimages")[0] == [
        {"path": str(dst), "name": "Tool-1.0", "added": True}
    ]
