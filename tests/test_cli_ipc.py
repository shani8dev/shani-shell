"""bin/shani's command groups against the shell's IPC surface.

`shani <group> <command>` is the documented way to drive the desktop, and every
group command maps to one function in shell.qml. A mapping to a function that
does not exist fails silently - the command prints nothing and returns 0 - so
every name in the table is checked against the shell itself, and every group
command is checked to have a mapping at all.
"""

import importlib.machinery
import importlib.util
import re
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
cli._register()
SHELL = (ROOT / "shani/shell.qml").read_text(encoding="utf-8")

start = SHELL.index("IpcHandler {")
end = SHELL.index("\n    }", start)
FUNCS = set(re.findall(r"^\s*function\s+(\w+)\s*\(", SHELL[start:end], re.M))

PAIRS = sorted(cli.IPC_NAMES)


def groups():
    return sorted(cli.GROUPS)


def pairs():
    return PAIRS


def commands_of(group):
    return [name for name, _args, _help in cli.GROUPS[group]]


# ---- the table -------------------------------------------------------------


def test_the_table_is_not_empty():
    assert len(cli.IPC_NAMES) > 100


def test_every_group_command_has_a_mapping():
    missing = [
        (group, name)
        for group in groups()
        for name in commands_of(group)
        if (group, name) not in cli.IPC_NAMES
    ]
    assert missing == []


def test_every_group_command_is_unique_within_its_group():
    for group in groups():
        names = commands_of(group)
        assert len(names) == len(set(names)), group


@pytest.mark.parametrize("group", groups())
def test_every_group_is_a_list_of_commands(group):
    assert cli.GROUPS[group]


@pytest.mark.parametrize("group,sub", pairs())
def test_the_mapping_points_at_a_function_the_shell_declares(group, sub):
    fn = cli.IPC_NAMES[(group, sub)]
    assert fn in FUNCS, (
        f"shani {group} {sub} calls {fn}, which shell.qml does not declare"
    )


@pytest.mark.parametrize("group,sub", pairs())
def test_the_mapping_is_camel_case(group, sub):
    """The convention the shell's own functions follow; a snake_case name is
    almost always a copy from somewhere else."""
    fn = cli.IPC_NAMES[(group, sub)]
    assert "_" not in fn, fn


# ---- the groups themselves -------------------------------------------------


def test_every_group_has_help_text():
    for group in groups():
        for _name, _args, help_text in cli.GROUPS[group]:
            assert help_text.strip(), group


def test_a_command_that_takes_an_argument_says_which():
    """`<ARG>` in the help is how `shani <group> <cmd> --help` tells you."""
    for group in groups():
        for name, args, help_text in cli.GROUPS[group]:
            # _run_group passes lowercase tokens to the IPC verbatim (a fixed
            # action, e.g. media next -> media("next")), upper-case tokens are
            # placeholders filled from the command line, and "-" is stdin.
            if any(a for a in args):
                joined = " ".join(args)
                assert (
                    ("<" in joined)
                    or joined.isupper()
                    or all(a.islower() or a == "-" for a in args)
                ), (group, name)
