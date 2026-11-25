"""Inventory checks that tie dev/render.sh to bin/shani's APPS table.

Static source tests — no shell is started and no render artifacts are needed.
They run in the default suite.  The visual (opt-in) pixel check lives in
test_render_surfaces.py; this file checks the source contracts that make that
check meaningful: every app with a state key is rendered, shot names are
unique, and shots that can silently show the previous surface declare a state
expectation.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import re
import shlex
from collections import Counter
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BIN_SHANI = ROOT / "bin" / "shani"
RENDER_SH = ROOT / "dev" / "render.sh"


@pytest.fixture(scope="module")
def shani_cli():
    loader = importlib.machinery.SourceFileLoader(
        "_shani_cli_inventory", str(BIN_SHANI)
    )
    spec = importlib.util.spec_from_loader("_shani_cli_inventory", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def render_src():
    return RENDER_SH.read_text(encoding="utf-8")


def _rendered_app_specs(src):
    """Run render.sh's own APPS loop and return {app name: state key}.

    Using the script's embedded Python, not a copy of it, means this catches a
    render.sh that drifts from bin/shani (a hardcoded allow-list, a stale
    OVERLAYS set, or a changed filter).
    """
    marker = "for spec in $(python3 - <<'PY'"
    start = src.index(marker)
    code_start = src.index("\n", start) + 1
    code_end = src.index("\nPY\n", code_start)
    code = src[code_start:code_end].replace("/work/bin/shani", str(BIN_SHANI))
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        exec(code, {})
    specs = {}
    for line in buf.getvalue().splitlines():
        name, key = line.split(":", 1)
        specs[name] = key
    return specs


def _capture_calls(src):
    """Return [(kind, tokens)] for each real capture/capture_current call."""
    calls = []
    for raw in src.splitlines():
        line = raw.split("#", 1)[0]  # no '#' appears in any capture argument
        for match in re.finditer(r"\b(capture_current|capture)\s+(.+)$", line):
            try:
                tokens = shlex.split(match.group(2).strip())
            except ValueError:
                continue
            # skip the function definitions `capture() {` / `capture_current() {`
            if not tokens or tokens[0].startswith(("(", "{")):
                continue
            calls.append((match.group(1), tokens))
    return calls


def _has_expectation(tokens):
    return any("d[" in t or "d.get(" in t for t in tokens)


def test_every_app_has_a_render_shot(shani_cli, render_src):
    """Every app with a state key in bin/shani must render as `app-<name>`.

    Apps with no state key are pointer-waiting actions (a screenshot, a colour
    pick) with no window to photograph; render.sh excludes them explicitly.
    The shot name is `app-` + the APPS key, so `scheduled-tasks` becomes
    `app-scheduled-tasks` — hyphenation is preserved, never normalised.
    """
    apps = shani_cli.APPS
    rendered = _rendered_app_specs(render_src)
    renderable = {name for name, spec in apps.items() if spec[8] is not None}

    missing = sorted(renderable - set(rendered))
    stale = sorted(set(rendered) - renderable)
    assert not missing, (
        "apps in bin/shani with a state key but no render shot (app-<name>): "
        + ", ".join(f"app-{n}" for n in missing)
    )
    assert not stale, (
        "render.sh captures app-<name> shots for names absent from bin/shani: "
        + ", ".join(stale)
    )

    # hyphenation: a key with a hyphen maps to that exact shot suffix
    rendered_shots = {f"app-{name}" for name in rendered}
    assert "app-scheduled-tasks" in rendered_shots
    assert "app-text-editor" in rendered_shots


def test_action_apps_are_not_captured_as_windows(shani_cli, render_src):
    """No-state-key apps are actions, and render.sh must not open them as apps."""
    actions = {name for name, spec in shani_cli.APPS.items() if spec[8] is None}
    rendered = _rendered_app_specs(render_src)
    overlap = sorted(actions & set(rendered))
    assert not overlap, (
        "action apps (no state key) cannot be captured as app windows: "
        + ", ".join(overlap)
    )
    assert "key is an action" in render_src, (
        "render.sh must document why action apps have no app-<name> shot"
    )


def test_capture_shot_names_are_unique(render_src):
    """Two shots with the same name overwrite each other in the contact sheet."""
    names = [tokens[0] for _, tokens in _capture_calls(render_src)]
    assert names, "no capture calls found in render.sh"
    dupes = sorted(name for name, count in Counter(names).items() if count > 1)
    assert not dupes, "duplicate shot names in render.sh: " + ", ".join(dupes)


def test_dynamic_shots_declare_state_expectations(render_src):
    """Loop/variable shots can show the previous surface; they need a guard.

    `cc-$sec`, `settings-$cat`, `clocks-$tab` and `app-$name` are generated in
    loops: a failed IPC leaves the prior surface on screen and the PNG looks
    plausible.  Each must pass an expectation over the shell's state.
    """
    dynamic = [
        (kind, tokens)
        for kind, tokens in _capture_calls(render_src)
        if "$" in tokens[0]
    ]
    assert dynamic, "no dynamically named shots found"
    unguarded = [tokens[0] for _, tokens in dynamic if not _has_expectation(tokens)]
    assert not unguarded, (
        "variable-named shots with no state expectation: " + ", ".join(unguarded)
    )


def test_capture_with_ipc_declares_state_expectation(render_src):
    """Any `capture` that fires an IPC to open a surface must check state.

    Desktop-only shots carry an empty command (`""`) — the wallpaper is their
    subject — so they are the sole exception.
    """
    unguarded = []
    for kind, tokens in _capture_calls(render_src):
        if kind != "capture":
            continue
        # capture <name> <cmd> <delay> [expectation]
        if len(tokens) >= 2 and tokens[1] and not _has_expectation(tokens[2:]):
            unguarded.append(tokens[0])
    assert not unguarded, (
        "capture() opens a surface but never checks state: " + ", ".join(unguarded)
    )
