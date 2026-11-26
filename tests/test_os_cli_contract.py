"""Every option the bridges pass to an OS command is one that command accepts.

The system pages run ShaniOS's own commands (shani-deploy, shani-health,
shani-reset, shani-etc-changes, ...) from shani-deploy's scripts/. In the dev
harness those are stand-ins that take any argument, so nothing here noticed
when "Clean up and optimise" ran `shani-deploy --cleanup --optimize --yes`:
the real shani-deploy has no --yes and stops with "Invalid option: --yes",
so the button could never work on an installed system.

This reads the bridges, finds each command line built from a constant that
names an OS command (or the *_ARGS default beside it), and checks every
option and subcommand word against the real command's parser in the checkout
beside this repo. Python parsers are read as argparse parsers, so a word in
a help string is not mistaken for an option. Skipped per command where the
source is not checked out.
"""

import ast
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = Path(
    os.environ.get("SHANI_DEPLOY_SCRIPTS", ROOT.parent / "shani-deploy" / "scripts")
)
BACKUP_CLI = Path(
    os.environ.get(
        "SHANI_BACKUP_CLI",
        ROOT.parent / "shani-backup" / "src" / "shani_backup" / "cli.py",
    )
)

# installed name -> source file: shani-deploy's scripts/, or shani-backup's package
COMMANDS = {
    "shani-deploy": "shani-deploy.sh",
    "shani-health": "shani-health.sh",
    "shani-reset": "shani-reset.sh",
    "shani-etc-changes": "shani-etc-changes",
    "shani-upgrade-adviser": "shani-upgrade-adviser.sh",
    "gen-efi": "gen-efi.sh",
    "shani-backup": "cli.py",
    "shani-cassini-save": "shani-cassini-save.sh",
}

# OS tools outside shani-deploy: their source is not beside this repo, so the
# strict stand-in is the contract. A stand-in that accepted any argument would
# hide a bad option exactly as the shani-deploy fakes once did (rule 5).
EXTERNAL_COMMANDS = {
    "sshd": "dev/fake-sshd.py",
    "visudo": "dev/fake-visudo.py",
    "exportfs": "dev/fake-exportfs.py",
    "testparm": "dev/fake-testparm.py",
    "pdbedit": "dev/fake-system-smb.py",
    "pcsc_scan": "dev/fake-system-access.py",
    "oathtool": "dev/fake-system-access.py",
}
ALL_COMMANDS = {**COMMANDS, **EXTERNAL_COMMANDS}


def source_path(command):
    """The real parser's source, or None when this checkout is not beside us."""
    if command in EXTERNAL_COMMANDS:
        path = ROOT / EXTERNAL_COMMANDS[command]
        return path if path.is_file() else None
    path = BACKUP_CLI if command == "shani-backup" else SCRIPTS / COMMANDS[command]
    return path if path.is_file() else None


def _head_name(node):
    head = node.elts[0]
    if isinstance(head, ast.Starred) and isinstance(head.value, ast.Name):
        return head.value.id
    return head.id if isinstance(head, ast.Name) else None


def _command_in(text):
    for name in ALL_COMMANDS:
        if re.search(r"(^|[/\s])" + re.escape(name) + r"($|\s)", text):
            return name
    return None


def _env_default(node):
    """'x' from os.environ.get("NAME", "x"), wrapped or not in shlex.split()."""
    for n in ast.walk(node):
        if (
            isinstance(n, ast.Call)
            and getattr(n.func, "attr", "") == "get"
            and len(n.args) == 2
            and isinstance(n.args[1], ast.Constant)
            and isinstance(n.args[1].value, str)
        ):
            env = n.args[0].value if isinstance(n.args[0], ast.Constant) else ""
            return str(env), n.args[1].value
    return None, None


def bridge_calls(root=ROOT):
    """(bridge file, command, [words]) for every command line the bridges build."""
    calls = []
    for path in sorted((Path(root) / "bridge").glob("*.py")):
        tree = ast.parse(path.read_text())
        consts, args_defaults = {}, []
        for node in tree.body:
            if (
                isinstance(node, ast.Assign)
                and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name)
            ):
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
        command = next(iter(consts.values()))
        # a module's *_ARGS default goes with its one command
        if len(set(consts.values())) == 1:
            for default in args_defaults:
                calls.append((path.name, command, shlex.split(default)))
        # A helper that builds [BACKUP, *args] is called with literal args;
        # command lines are built there, not beside the constant.
        runners = {
            node.name
            for node in ast.walk(tree)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and any(
                isinstance(n, ast.List) and n.elts and _head_name(n) in consts
                for n in ast.walk(node)
            )
        }
        for node in ast.walk(tree):
            if isinstance(node, ast.List) and node.elts and _head_name(node) in consts:
                words = [
                    e.value
                    for e in node.elts[1:]
                    if isinstance(e, ast.Constant) and isinstance(e.value, str)
                ]
                calls.append((path.name, consts[_head_name(node)], words))
            elif (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Name)
                and node.func.id in runners
                and node.args
                and isinstance(node.args[0], ast.List)
            ):
                words = [
                    e.value
                    for e in ast.walk(node.args[0])
                    if isinstance(e, ast.Constant) and isinstance(e.value, str)
                ]
                calls.append((path.name, command, words))
    return calls


def _argparse_words(text):
    """Options and subcommands the script actually gives to argparse."""
    words = set()
    for node in ast.walk(ast.parse(text)):
        if (
            not isinstance(node, ast.Call)
            or not isinstance(node.func, ast.Attribute)
            or node.func.attr not in ("add_parser", "add_argument")
        ):
            continue
        if (
            node.args
            and isinstance(node.args[0], ast.Constant)
            and isinstance(node.args[0].value, str)
        ):
            words.add(node.args[0].value)
        for kw in node.keywords:
            if kw.arg == "choices":
                for item in ast.walk(kw.value):
                    if isinstance(item, ast.Constant) and isinstance(item.value, str):
                        words.add(item.value)
    return words


def accepts(command, word):
    """Whether the command's own parser knows this option or subcommand."""
    path = source_path(command)
    if path is None:
        pytest.skip(f"no {command} parser beside this repo")
    text = path.read_text(errors="ignore")
    if command in EXTERNAL_COMMANDS:
        # The stand-in's strict argv table names every option it will accept.
        known = {
            n.value
            for n in ast.walk(ast.parse(text))
            if isinstance(n, ast.Constant) and isinstance(n.value, str)
        }
        return word in known
    if text.startswith("#!/usr/bin/env python") or text.startswith("#!/usr/bin/python"):
        return word in _argparse_words(text)
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
    assert ("backup.py", "shani-backup") in found


def test_a_made_up_option_is_caught():
    if source_path("shani-deploy") is None:
        pytest.skip("no shani-deploy scripts beside this repo")
    assert not accepts("shani-deploy", "--yes")
    assert accepts("shani-deploy", "--cleanup")
    assert not accepts("gen-efi", "--yes")


def test_gen_efi_checks_its_json_flag_in_a_comparison():
    # `[[ "$2" == "--json" ]]` is the parser, not a case label
    assert accepts("gen-efi", "--json")
    assert accepts("gen-efi", "recovery-key")


def test_the_backup_parser_is_read_as_argparse():
    if source_path("shani-backup") is None:
        pytest.skip("no shani-backup checkout beside this repo")
    assert not accepts("shani-backup", "--yes")
    assert accepts("shani-backup", "--json")
    assert accepts("shani-backup", "snapshot")


def test_a_made_up_backup_option_in_a_bridge_list_is_caught(tmp_path):
    if source_path("shani-backup") is None:
        pytest.skip("no shani-backup checkout beside this repo")
    folder = tmp_path / "bridge"
    folder.mkdir()
    (folder / "probe.py").write_text(
        "import os, shlex\n"
        'BACKUP = shlex.split(os.environ.get("SHANI_BACKUP_TOOL", "shani-backup"))\n'
        "def listing():\n"
        '    return [BACKUP, "home", "--yes", "--json"]\n'
        "def run(args):\n"
        "    return [BACKUP, *args]\n"
        "def restore():\n"
        '    return run(["restore", "--yes", "--json"])\n'
    )
    found = bridge_calls(tmp_path)
    assert ("probe.py", "shani-backup", ["home", "--yes", "--json"]) in found
    assert ("probe.py", "shani-backup", ["restore", "--yes", "--json"]) in found
    assert not accepts("shani-backup", "--yes")


@pytest.mark.parametrize("command", sorted(ALL_COMMANDS))
def test_every_option_the_bridges_pass_is_accepted(command):
    if source_path(command) is None:
        pytest.skip(f"no {command} parser beside this repo")
    wrong = []
    for bridge, used, words in bridge_calls():
        if used != command:
            continue
        for word in words:
            if word.startswith("-") or re.fullmatch(r"[a-z][a-z0-9-]+", word):
                if not accepts(command, word):
                    wrong.append(f"{bridge}: {used} {word}")
    assert wrong == []


@pytest.mark.parametrize("command", sorted(EXTERNAL_COMMANDS))
def test_external_standin_rejects_an_option_the_real_tool_rejects(command, tmp_path):
    path = source_path(command)
    if path is None:
        pytest.skip(f"no {command} stand-in")
    env = dict(os.environ)
    env["FAKE_SYSTEM_ACCESS"] = str(tmp_path)
    env["FAKE_SYSTEM_NFS"] = str(tmp_path)
    env["FAKE_SYSTEM_SMB"] = str(tmp_path)
    # fake-system-access.py and the system-*-samba stand-ins pick their tool
    # from argv[0], as the real tools are invoked by name.
    runner = tmp_path / command
    runner.symlink_to(path)
    result = subprocess.run(
        [sys.executable, str(runner), "--not-an-option-of-this-tool"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode != 0, f"{command} stand-in accepted a made-up option"
