"""Static contracts that make a render run trustworthy.

No shell is started and no render artifacts are read.  These tests assert the
source-level safety nets: the harness guards against blank frames, retries
lost IPCs, waits after closing, and fails loudly; shell.qml exposes every
open command and state key that bin/shani's APPS table names.

The opt-in pixel check itself lives in test_render_surfaces.py — this file
only verifies the contracts it relies on, so it runs in the default suite.
"""

import importlib.machinery
import importlib.util
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
RENDER_SH = ROOT / "dev" / "render.sh"
SHELL_QML = ROOT / "shani" / "shell.qml"
SURFACES_TEST = ROOT / "tests" / "test_render_surfaces.py"
BIN_SHANI = ROOT / "bin" / "shani"


@pytest.fixture(scope="module")
def render_src():
    return RENDER_SH.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def shell_src():
    return SHELL_QML.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def shani_cli():
    loader = importlib.machinery.SourceFileLoader(
        "_shani_cli_contracts", str(BIN_SHANI)
    )
    spec = importlib.util.spec_from_loader("_shani_cli_contracts", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def _fn_body(src, name):
    """Return the body of a top-level shell function `name() { ... }`."""
    m = re.search(r"^\s*" + re.escape(name) + r"\s*\(\)\s*\{", src, re.M)
    if not m:
        return None
    depth = 0
    for i in range(m.end() - 1, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[m.end() : i]
    return None


def _state_block(src):
    m = re.search(r"function state\(\)\s*:\s*string\s*\{", src)
    assert m, "shell.qml has no state() IPC function"
    end = src.find("function webappAdd", m.end())
    return src[m.end() : end if end != -1 else len(src)]


def _head(value):
    """An APPS IPC entry is either a string command or [command, ...]."""
    return value if isinstance(value, str) else value[0]


# ---- render harness contracts -------------------------------------------


def test_has_desktop_baseline_reference(render_src):
    """The plain desktop is captured first and used as the pixel baseline."""
    assert re.search(r'^\s*capture desktop-rest\s+""', render_src, re.M), (
        "render.sh must capture the desktop baseline as its first shot"
    )
    assert re.search(r'BASE="\$OUTDIR/01-desktop-rest\.png"', render_src), (
        "render.sh must name the desktop baseline used by the blank-frame guard"
    )
    surfaces = SURFACES_TEST.read_text(encoding="utf-8")
    assert "01-desktop-rest.png" in surfaces, (
        "the opt-in check must reference the desktop baseline PNG"
    )


def test_has_visual_blank_frame_guard(render_src):
    """A surface that never drew must not pass as a plausible-looking PNG."""
    guard = _fn_body(render_src, "frame_is_blank")
    assert guard is not None, "render.sh has no frame_is_blank() guard"
    assert "PIL" in guard and "12" in guard, (
        "frame_is_blank() must compare frame centres against the baseline"
    )
    assert _fn_body(render_src, "needs_visual") is not None, (
        "render.sh must limit the visual guard to centred surfaces"
    )
    shoot = _fn_body(render_src, "shoot")
    assert shoot is not None and "frame_is_blank" in shoot, (
        "shoot() must reject a blank frame before logging a PASS"
    )
    surfaces = SURFACES_TEST.read_text(encoding="utf-8")
    assert "BLANK_THRESHOLD" in surfaces and "def _center" in surfaces, (
        "the opt-in check must compare frame centres against the baseline"
    )
    assert "SHANI_RENDER_CHECK" in surfaces, (
        "the opt-in gate must remain in the visual check"
    )
    assert 'waitfor "$3"' in render_src and "check_want" in render_src


def test_has_retry(render_src):
    """A lost IPC under load is reissued once before the surface is called bad."""
    body = _fn_body(render_src, "open_surface")
    assert body is not None, "render.sh has no open_surface() retry helper"
    assert body.count('ipc "$2"') >= 2, (
        "open_surface() must reissue the IPC once on failure"
    )
    assert body.count('waitfor "$3"') >= 2, (
        "open_surface() must re-check state after the retry"
    )
    assert "reissue it once" in render_src
    # a blank-looking centred surface is re-opened and re-shot, not left as-is
    shoot = _fn_body(render_src, "shoot") or ""
    assert shoot.count("grim") >= 2 and 'ipc "$_cmd"' in shoot, (
        "shoot() must retry the IPC and recapture a blank frame"
    )


def test_has_close_wait(render_src):
    """Closing one surface must settle before the next shot is taken."""
    body = _fn_body(render_src, "close_all")
    assert body is not None, "render.sh has no close_all() helper"
    assert re.search(r"ipc\s+dismissAll\b", body), (
        "close_all() must dismiss the tracked surfaces"
    )
    assert re.search(r"\bwaitfor\b", body) and re.search(r"\bsleep\s+", body), (
        "close_all() must wait for panels to clear and for the frame to settle"
    )


def test_has_fail_path(render_src):
    """A surface that never came up makes the run fail, not log a PASS."""
    assert 'log "FAIL:' in render_src
    assert "RESULT shot-$1 FAIL" in render_src
    assert "failed=$((failed+1))" in render_src
    assert "exit 1" in render_src


# ---- shell.qml contracts -------------------------------------------------


def test_every_apps_open_command_exists(shani_cli, shell_src):
    """Each APPS entry's open IPC command is defined in shell.qml."""
    defined = set(re.findall(r"function\s+(\w+)\s*\(", shell_src))
    missing = []
    for name, spec in shani_cli.APPS.items():
        plain, with_file = spec[6], spec[7]
        commands = set()
        if plain:
            commands.add(_head(plain))
        if with_file:
            commands.add(_head(with_file))
        for command in commands:
            if command not in defined:
                missing.append((name, command))
    assert not missing, (
        "APPS open commands with no function in shell.qml: "
        + ", ".join(f"{name} -> {cmd}" for name, cmd in missing)
    )


def test_every_apps_state_key_is_in_state_ipc_block(shani_cli, shell_src):
    """Each APPS state key is reported by the state() IPC call."""
    keys = set(re.findall(r"\b(\w+)\s*:", _state_block(shell_src)))
    missing = [
        (name, spec[8])
        for name, spec in shani_cli.APPS.items()
        if spec[8] is not None and spec[8] not in keys
    ]
    assert not missing, "APPS state keys missing from state() IPC: " + ", ".join(
        f"{name} -> {key}" for name, key in missing
    )
