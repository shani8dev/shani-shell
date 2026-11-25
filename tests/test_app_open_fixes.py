"""Static guard for the app openers the render harness drives.

``dev/render.sh`` starts each app with ``shani app NAME`` and waits on the
state key from ``bin/shani``'s APPS table before photographing it. If the IPC
call is missing, or the state key is not exposed by the shell's ``state()``,
the shot either fails or photographs the desktop while the harness logs PASS.
These tests read the files as text — no running shell — so the two tables and
the shell cannot drift apart unnoticed.
"""

import importlib.machinery
import importlib.util
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def _apps():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin/shani"))
    module = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("shani_cli", loader)
    )
    loader.exec_module(module)
    return module.APPS


SHELL = (ROOT / "shani/shell.qml").read_text(encoding="utf-8")


def _ipc_block():
    start = SHELL.index("IpcHandler {")
    return SHELL[start : SHELL.index("\n    }", start)]


def _state_block():
    start = SHELL.index("function state(): string {")
    return SHELL[start : SHELL.index("\n        }", start)]


IPC_FUNCTIONS = set(re.findall(r"^\s*function\s+(\w+)\s*\(", _ipc_block(), re.M))
STATE_KEYS = set(re.findall(r"\b(\w+)\s*:", _state_block()))


def test_every_apps_open_command_has_an_ipc_function():
    """spec[6]/spec[7] name functions the shell's IpcHandler must declare."""
    missing = [
        (name, call[0])
        for name, spec in _apps().items()
        for call in (spec[6], spec[7])
        if isinstance(call, list) and call and call[0] not in IPC_FUNCTIONS
    ]
    assert not missing, f"APPS call IPC the shell does not declare: {missing}"


def test_every_apps_state_key_is_exposed_by_state():
    """spec[8] is the key dev/render.sh waits on; state() must return it."""
    missing = sorted(
        (name, spec[8])
        for name, spec in _apps().items()
        if spec[8] and spec[8] not in STATE_KEYS
    )
    assert not missing, f"APPS state keys missing from state(): {missing}"


def test_lazyloader_sources_exist():
    """Every LazyLoader source path must point at a real QML file."""
    sources = re.findall(r'LazyLoader\s*\{[^}]*?source:\s*"([^"]+)"', SHELL, re.S)
    assert sources, "no LazyLoader sources found — parsing broke"
    missing = sorted({s for s in sources if not (ROOT / "shani" / s).is_file()})
    assert not missing, f"LazyLoader sources that do not exist: {missing}"


# The openers behind the shots that were blank while their state key was set.
# Each row: IPC function -> fragment its body must contain to raise/window the
# flag that both state() and the matching LazyLoader/AppWindow watch.
OPENERS = {
    "clocksOpen": ("Ui.clocks = true",),
    "dictionaryOpen": ("Ui.dictionary = true",),
    "scheduledOpen": ("Ui.scheduled = true",),
    "databaseBrowserOpen": ("Ui.databaseBrowser = true",),
    "disksOpen": ("Ui.disks = true",),
    "authenticatorOpen": ("Ui.authenticator = true",),
    "cloudSyncOpen": ("Ui.cloudSync = true",),
    "mediaOpen": ("PlayQueue.open(path)",),
    "mediaPage": ("PlayQueue.page = page",),
    "radioShow": ('PlayQueue.open("")', 'PlayQueue.page = "radio"'),
    "liveTvOpen": ('PlayQueue.open("")', 'PlayQueue.page = "live"'),
    "quickLook": ("QuickLook.open(path",),
}


@pytest.mark.parametrize("fn,fragments", sorted(OPENERS.items()))
def test_rendered_app_opener_sets_its_flag(fn, fragments):
    body = re.search(rf"function\s+{fn}\s*\([^)]*\)\s*\{{(.*?)\}}", _ipc_block(), re.S)
    assert body, f"{fn}() is not declared in the IpcHandler"
    for fragment in fragments:
        assert fragment in body.group(1), (
            f"{fn}() does not raise the flag the render harness waits on: {fragment}"
        )
