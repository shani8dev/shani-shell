"""The greeter and the first-boot wizard load every module their files import.

Both are their own Quickshell configs that share the shell's Common/ through a
symlink. Quickshell treats a directory as one module: when a single file in
Common/ imports `qs.Services` and the config has no Services/, every type in
Common/ is "unavailable" and the whole config fails to load. That is what
happened (Common/Ui.qml, AppWindow.qml and HoverPeek.qml started importing
qs.Services): no login screen and no first-boot wizard, while every shell
check still passed.

This walks every QML file reachable from each config and checks each
`import qs.X` names a directory present in that config.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
IMPORT = re.compile(r"^\s*import\s+qs\.([A-Za-z0-9_.]+)", re.M)


def _imports(config: Path) -> dict[str, list[str]]:
    seen: dict[str, list[str]] = {}
    # followlinks: Common/ and Services/ are symlinks into the shell's tree
    files = [Path(d) / f for d, _, fs in os.walk(config, followlinks=True) for f in fs if f.endswith(".qml")]
    for qml in files:
        for mod in IMPORT.findall(qml.read_text(errors="replace")):
            seen.setdefault(mod, []).append(str(qml.relative_to(config)))
    return seen


@pytest.mark.parametrize("name", ["greeter", "setup"])
def test_every_qs_import_resolves(name):
    config = ROOT / name
    missing = {
        mod: files[:3]
        for mod, files in _imports(config).items()
        if not (config / mod.replace(".", "/")).is_dir()
    }
    assert missing == {}, f"{name} cannot load: {missing}"


@pytest.mark.parametrize("name", ["greeter", "setup"])
def test_the_control_sees_common_imports(name):
    # an empty walk would pass the test above: Common/'s own files must be seen
    assert any(f.startswith("Common/") for f in _imports(ROOT / name).get("Common", []))


# a relative script or file import ("../Modules/X.js") resolves from the file's
# own folder: Services/ChronoaSettings.qml importing ../Modules/Settings/*.js
# loaded in the shell but not in the greeter or setup, whose Services/ is a
# link with no Modules/ beside it - and the whole Services module failed.
REL = re.compile(r'^\s*import\s+"([^"]+)"', re.M)


@pytest.mark.parametrize("name", ["greeter", "setup"])
def test_every_relative_import_resolves(name):
    config = ROOT / name
    missing = []
    for d, _, fs in os.walk(config, followlinks=True):
        for f in fs:
            if not f.endswith(".qml"):
                continue
            qml = Path(d) / f
            for rel in REL.findall(qml.read_text(errors="replace")):
                if "://" in rel:
                    continue
                # resolved as Quickshell does: from the folder as seen in this config
                target = Path(os.path.normpath(Path(d) / rel))
                if not target.exists():
                    missing.append(f"{qml.relative_to(config)}: {rel}")
    assert missing == [], f"{name} cannot load: {missing[:5]}"
