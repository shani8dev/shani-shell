"""bin/shani's app register, checked against the shell.

`APPS` in bin/shani is what writes the desktop entries, what `shani app` lists,
and what the shell's own IPC is called through. A wrong entry there is an app
that does not start, or a desktop entry the panel hides - and neither fails
loudly. So every entry is checked against the shell itself: the IPC function it
names must exist, the state key the suite reads must exist, and the desktop
entry it writes must be one a panel will show.
"""

import importlib.machinery
import importlib.util
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def load_cli():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin/shani"))
    spec = importlib.util.spec_from_loader("shani_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


cli = load_cli()
APPS = cli.APPS
SHELL = (ROOT / "shani/shell.qml").read_text(encoding="utf-8")

# the `state` object the suite reads over IPC
STATE_START = SHELL.index("state: {") if "state: {" in SHELL else 0
STATE_BLOCK = SHELL[STATE_START:]


def ipc_functions():
    """Every function declared in the IpcHandler."""
    start = SHELL.index("IpcHandler {")
    end = SHELL.index("\n    }", start)
    block = SHELL[start:end]
    return set(re.findall(r"^\s*function\s+(\w+)\s*\(", block, re.M))


def state_keys():
    return set(re.findall(r"(\w+):\s", STATE_BLOCK))


FUNCS = ipc_functions()
KEYS = state_keys()


def app_names():
    return sorted(APPS)


def spec(name):
    return APPS[name]


# ---- the register itself ---------------------------------------------------


def test_the_register_is_not_empty():
    assert len(APPS) >= 40


def test_every_name_is_lowercase_and_hyphenated():
    bad = [n for n in APPS if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", n)]
    assert bad == []


def test_no_duplicate_desktop_ids():
    ids = [s[0] for s in APPS.values()]
    assert len(ids) == len(set(ids))


@pytest.mark.parametrize("name", app_names())
def test_the_desktop_id_is_ours(name):
    assert spec(name)[0].startswith("dev.shani.")


@pytest.mark.parametrize("name", app_names())
def test_every_app_has_a_title(name):
    assert spec(name)[1].strip() != ""


@pytest.mark.parametrize("name", app_names())
def test_every_app_says_what_it_is_for(name):
    assert spec(name)[2].strip() != ""


@pytest.mark.parametrize("name", app_names())
def test_every_app_has_an_icon(name):
    assert spec(name)[3].strip() != ""


@pytest.mark.parametrize("name", app_names())
def test_every_app_has_categories(name):
    assert spec(name)[4].strip() != ""


# ---- the register against the shell ---------------------------------------


@pytest.mark.parametrize("name", app_names())
def test_the_ipc_function_it_calls_exists(name):
    """`shani app NAME` calls this; if the shell does not declare it, the call
    is a no-op and the app never opens."""
    plain = spec(name)[6]
    if plain:
        assert plain[0] in FUNCS, f"{name} calls {plain[0]}, which shell.qml does not declare"


@pytest.mark.parametrize("name", app_names())
def test_the_state_key_the_suite_reads_exists(name):
    key = spec(name)[8]
    if key:
        assert key in KEYS, (
            f"{name} reports {key}, which the state object does not have"
        )


# ---- the desktop entry -----------------------------------------------------


@pytest.mark.parametrize("name", app_names())
def test_the_desktop_entry_is_well_formed(name):
    entry = cli.desktop_entry(name)
    lines = entry.strip().splitlines()
    assert lines[0] == "[Desktop Entry]"
    keys = dict(line.split("=", 1) for line in lines[1:] if "=" in line)
    assert keys["Type"] == "Application"
    assert keys["Name"] == spec(name)[1]
    assert keys["Exec"].startswith("shani app " + name)
    # a window with no startup notification: the shell draws it
    assert keys["StartupNotify"] == "false"


@pytest.mark.parametrize("name", app_names())
def test_a_plain_app_says_it_opens_a_file(name):
    """NoDisplay=true is for an action (a screenshot, a colour pick), not for
    an app nobody can start from the launcher."""
    s = spec(name)
    entry = cli.desktop_entry(name)
    if s[6] is None:
        assert "NoDisplay=true" in entry
    else:
        assert "NoDisplay" not in entry


@pytest.mark.parametrize("name", app_names())
def test_the_mimetypes_are_real_mime_types(name):
    for m in spec(name)[5] or []:
        assert re.fullmatch(r"[a-z0-9.+-]+/[a-z0-9.+-]+", m), m
