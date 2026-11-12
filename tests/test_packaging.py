"""The package holds what the shell reaches for.

Runs shani-pkgbuilds/shani-shell's package() on a copy of this tree and looks
at what lands in $pkgdir: every /usr/lib/shani-shell/ and /usr/share/shani/
path the QML names, and every module a bridge script imports from its own
directory. The PKGBUILD's hand-kept list once left out screensaver.py (the
packaged bridge died at import) and characters.py; nothing here ran the
package, so nothing noticed.

Skipped where shani-pkgbuilds is not checked out beside this repo.
"""
import ast
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PKGBUILD = Path(os.environ.get("SHANI_SHELL_PKGBUILD", ROOT.parent / "shani-pkgbuilds" / "shani-shell" / "PKGBUILD"))

pytestmark = pytest.mark.skipif(not PKGBUILD.exists() or not shutil.which("bash"), reason="no shani-pkgbuilds beside this repo")


@pytest.fixture(scope="module")
def pkgdir(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("pkg")
    src = tmp / "src" / "shani-shell"
    # a copy: package() edits a unit file in place
    shutil.copytree(ROOT, src, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", "out", "__pycache__", ".pytest_cache", "docs", "tests", "dev"))
    out = tmp / "pkg"
    out.mkdir()
    run = subprocess.run(
        ["bash", "-ec", 'source "$1"; srcdir="$2" pkgdir="$3"; package', "bash", str(PKGBUILD), str(src.parent), str(out)],
        capture_output=True, text=True)
    assert run.returncode == 0, run.stderr[-2000:]
    return out


def qml_sources():
    for top in ("shani", "greeter", "setup"):
        for path in (ROOT / top).rglob("*"):
            if path.suffix in (".qml", ".js") and path.is_file():
                yield path


def test_every_path_the_shell_names_is_packaged(pkgdir):
    wanted = set()
    for path in qml_sources():
        wanted.update(re.findall(r'"(/usr/(?:lib/shani-shell|share/shani|share/backgrounds/shani)/[^"\s$]+)"', path.read_text(errors="ignore")))
    assert wanted, "the scan found nothing: the pattern is wrong"
    missing = sorted(p for p in wanted if not (pkgdir / p.lstrip("/")).exists())
    assert missing == []


def test_bridge_scripts_find_their_own_modules(pkgdir):
    lib = pkgdir / "usr/lib/shani-shell"
    local = {p.stem for p in (ROOT / "bridge").glob("*.py")}
    missing = []
    for script in lib.glob("*.py"):
        for node in ast.walk(ast.parse(script.read_text())):
            names = [a.name for a in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) and node.level == 0 else []
            for name in names:
                top = (name or "").split(".")[0]
                if top in local and not (lib / (top + ".py")).exists():
                    missing.append(f"{script.name} imports {top}")
    assert missing == []


def test_the_configs_are_packaged_whole(pkgdir):
    for name in ("shani", "shani-greeter", "shani-setup"):
        assert (pkgdir / "etc/xdg/quickshell" / name / "shell.qml").exists(), name
    # the greeter's and setup's Common is a symlink in the repo, a real copy in the package
    for name in ("shani-greeter", "shani-setup"):
        common = pkgdir / "etc/xdg/quickshell" / name / "Common"
        assert common.is_dir() and not common.is_symlink(), name


def test_the_apps_have_desktop_entries(pkgdir):
    apps = pkgdir / "usr/share/applications"
    names = {p.name for p in apps.glob("dev.shani.*.desktop")}
    assert {"dev.shani.TextEditor.desktop", "dev.shani.Files.desktop", "dev.shani.Calculator.desktop"} <= names
    for entry in apps.glob("dev.shani.*.desktop"):
        text = entry.read_text()
        assert re.search(r"^Exec=shani app [a-z-]+( %u)?$", text, re.M), entry.name
        # an app that only opens files is offered for them, and is not in the grid
        if "%u" in text and "MimeType=" not in text and "NoDisplay=true" in text:
            raise AssertionError(f"{entry.name} is hidden and handles nothing")


def test_every_default_app_of_the_image_is_in_the_image(pkgdir):
    """/etc/skel's mimeapps.list named org.gnome.TextEditor for 22 text types
    after its Flatpak had left the niri image: opening a text file did nothing.
    A default has to be an app of the shell's, a Flatpak of the niri profile,
    or one of the natively packaged apps named here."""
    desk = PKGBUILD.parent.parent / "shani-desktop-niri"
    mimeapps = desk / "etc/skel/.config/mimeapps.list"
    flatpaks = ROOT.parent / "shani-install-media/image_profiles/niri/flatpak-packages.txt"
    if not mimeapps.exists() or not flatpaks.exists():
        pytest.skip("no shani-desktop-niri or shani-install-media beside this repo")
    shipped = {line.strip() for line in flatpaks.read_text().splitlines() if line.strip() and not line.startswith("#")}
    native = {"org.gnome.Nautilus", "org.gnome.FileRoller", "dev.shani.Link.Dial", "dev.shani.Link.App", "dev.shani.cassini"}
    ours = {p.stem: p.read_text() for p in (pkgdir / "usr/share/applications").glob("*.desktop")}
    missing, unhandled = set(), set()
    for line in mimeapps.read_text().splitlines():
        if "=" not in line or line.startswith("#"):
            continue
        mime, apps = line.split("=", 1)
        for app in filter(None, apps.split(";")):
            ident = app.removesuffix(".desktop")
            if ident in ours:
                types = re.search(r"^MimeType=(.*)$", ours[ident], re.M)
                if mime not in (types.group(1).split(";") if types else []):
                    unhandled.add(f"{mime} -> {ident}")
            elif ident not in shipped and ident not in native:
                missing.add(ident)
    assert missing == set(), "defaults naming apps the image does not ship"
    assert unhandled == set(), "defaults the shell's app does not declare"
