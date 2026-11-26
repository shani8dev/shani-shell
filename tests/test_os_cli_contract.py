"""Every option the bridges pass to an OS command is one that command accepts.

The system pages run ShaniOS's own commands (shani-deploy, shani-health,
shani-reset, shani-etc-changes, ...) from shani-deploy's scripts/. In the dev
harness those are stand-ins that take any argument, so nothing here noticed
when "Clean up and optimise" ran `shani-deploy --cleanup --optimize --yes`:
the real shani-deploy has no --yes and stops with "Invalid option: --yes",
so the button could never work on an installed system.

This reads the bridges, finds each command line built from a constant that
names an OS command (or the *_ARGS default beside it), and checks every
option and subcommand word against the real script's parser in the
shani-deploy checkout beside this repo. Skipped where there is none.
"""

import ast
import os
import re
import shlex
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = Path(os.environ.get("SHANI_DEPLOY_SCRIPTS", ROOT.parent / "shani-deploy" / "scripts"))

pytestmark = pytest.mark.skipif(not SCRIPTS.is_dir(), reason="no shani-deploy beside this repo")

# installed name -> source file in shani-deploy/scripts (the PKGBUILD drops ".sh")
COMMANDS = {
    "shani-deploy": "shani-deploy.sh",
    "shani-health": "shani-health.sh",
    "shani-reset": "shani-reset.sh",
    "shani-etc-changes": "shani-etc-changes",
    "shani-upgrade-adviser": "shani-upgrade-adviser.sh",
    "gen-efi": "gen-efi.sh",
}


def _command_in(text):
    for name in COMMANDS:
        if re.search(r"(^|[/\s])" + re.escape(name) + r"($|\s)", text):
            return name
    return None


def _env_default(node):
    """'x' from os.environ.get("NAME", "x"), wrapped or not in shlex.split()."""
    for n in ast.walk(node):
        if (isinstance(n, ast.Call) and getattr(n.func, "attr", "") == "get" and len(n.args) == 2
                and isinstance(n.args[1], ast.Constant) and isinstance(n.args[1].value, str)):
            env = n.args[0].value if isinstance(n.args[0], ast.Constant) else ""
            return str(env), n.args[1].value
    return None, None


def bridge_calls():
    """(bridge file, command, [words]) for every command line the bridges build."""
    calls = []
    for path in sorted((ROOT / "bridge").glob("*.py")):
        tree = ast.parse(path.read_text())
        consts, args_defaults = {}, []
        for node in tree.body:
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                env, default = _env_default(node.value)
                if default is None:
                    continue
                cmd = _command_in(default)
                if cmd:
                    consts[node.targets[0].id] = cmd
                elif env.endswith("_ARGS"):
                    args_defaults.append(default)
        if not consts:
            continue
        # a module's *_ARGS default goes with its one command
        if len(set(consts.values())) == 1:
            for default in args_defaults:
                calls.append((path.name, next(iter(consts.values())), shlex.split(default)))
        for node in ast.walk(tree):
            if not isinstance(node, ast.List) or not node.elts:
                continue
            head = node.elts[0]
            name = head.value.id if isinstance(head, ast.Starred) and isinstance(head.value, ast.Name) else \
                head.id if isinstance(head, ast.Name) else None
            if name in consts:
                words = [e.value for e in node.elts[1:] if isinstance(e, ast.Constant) and isinstance(e.value, str)]
                calls.append((path.name, consts[name], words))
    return calls


def accepts(command, word):
    """Whether the command's own parser knows this option or subcommand."""
    text = (SCRIPTS / COMMANDS[command]).read_text(errors="ignore")
    quoted = re.search(r"""["']""" + re.escape(word) + r"""["']""", text) is not None
    if text.startswith("#!/usr/bin/env python") or text.startswith("#!/usr/bin/python"):
        return quoted
    # a bash case label: `--json)`, `-c|--cleanup)`, `tpm2-status)`
    if re.search(r"(^|[\s|(])" + re.escape(word) + r"(\)|\|)", text, re.M) is not None:
        return True
    # gen-efi checks a flag with `[[ "${2:-}" == "--json" ]]`, not a case label;
    # a quoted comparison is the parser accepting the word too.
    return re.search(r'[=]=?\s*["\']' + re.escape(word) + r'["\']', text) is not None


def test_the_scan_finds_the_known_calls():
    found = {(f, c) for f, c, _ in bridge_calls()}
    assert ("system_maintenance.py", "shani-deploy") in found
    assert ("system_health.py", "shani-health") in found


def test_a_made_up_option_is_caught():
    # the negative control: the check cannot pass everything
    assert not accepts("shani-deploy", "--yes")
    assert accepts("shani-deploy", "--cleanup")
    assert not accepts("gen-efi", "--yes")


def test_gen_efi_checks_its_json_flag_in_a_comparison():
    # `[[ "$2" == "--json" ]]` is the parser, not a case label
    assert accepts("gen-efi", "--json")
    assert accepts("gen-efi", "recovery-key")


def test_every_option_the_bridges_pass_is_accepted():
    wrong = []
    for bridge, command, words in bridge_calls():
        for word in words:
            if word.startswith("-") or re.fullmatch(r"[a-z][a-z0-9-]+", word):
                if not accepts(command, word):
                    wrong.append(f"{bridge}: {command} {word}")
    assert wrong == []
