"""Every `shani <group> <command>` must reach a function the shell defines.

A command whose IPC name falls through to the command itself can look fine in
`--help` and still do nothing when run. This is the guard test_wiring.py lacks.
"""

import importlib.machinery
import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin/shani"))
spec = importlib.util.spec_from_loader(loader.name, loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)

# Commands handled entirely in the CLI, or deliberately mapping to a shell
# function whose name does not follow the command name.
LOCAL = {
    ("app", "list"),
    ("doctor", "run"),
    ("state", "show"),
}


def test_every_cli_command_reaches_an_ipc_function():
    shell = (ROOT / "shani/shell.qml").read_text()
    functions = set(re.findall(r"function\s+(\w+)\s*\(", shell))
    missing = []
    for group, commands in cli.GROUPS.items():
        for name, _args, _help in commands:
            if (group, name) in LOCAL:
                continue
            fn = cli._fn_name(group, name)
            if fn not in functions:
                missing.append(f"{group} {name} -> {fn}()")
    assert not missing, "CLI commands with no shell function: " + ", ".join(missing)


def _state_keys(shell: str) -> set:
    """Keys named in the shell's state() IPC reply."""
    lines = shell.splitlines()
    start = next(i for i, l in enumerate(lines) if "function state(" in l)
    depth = 0
    end = start
    for i in range(start, len(lines)):
        depth += lines[i].count("{") - lines[i].count("}")
        if depth <= 0 and i > start:
            end = i
            break
    return set(re.findall(r"\b([A-Za-z_]\w*)\s*:", "\n".join(lines[start:end])))


def test_render_ipcs_and_wants_are_real():
    """Every IPC the render harness sends must exist; every state key it
    asserts must be one state() actually reports. A typo here silently leaves
    the previous surface on screen, producing a plausible-looking wallpaper."""
    shell = (ROOT / "shani/shell.qml").read_text()
    functions = set(re.findall(r"function\s+(\w+)\s*\(", shell))
    keys = _state_keys(shell)
    render = (ROOT / "dev/render.sh").read_text()

    # ipc_line "cmd args" (dev/harness.sh) is how render.sh calls the shell
    cmds = set(re.findall(r"\bipc(?:_line)?\s+\"?([A-Za-z_]\w*)", render))
    cmds |= {
        m.group(1).split()[0]
        for m in re.finditer(r'\bcapture\s+\S+\s+"([A-Za-z_][^"]*)"', render)
    }
    # "qs ... ipc call shani <fn>" is CLI syntax, not an IPC command name
    cmds.discard("call")
    assert not (cmds - functions), "render IPCs with no shell function: " + ", ".join(
        sorted(cmds - functions)
    )

    used = set(re.findall(r"d\['([^']+)'\]", render)) | set(
        re.findall(r"d\.get\('([^']+)'\)", render)
    )
    used = {k for k in used if "$" not in k}  # runtime shell substitution
    assert not (used - keys), "render wants unknown state keys: " + ", ".join(
        sorted(used - keys)
    )

    # `waitfor` evaluates each expression as PYTHON. A JS-ism like
    # `d['x'].length` names a real key but raises AttributeError at runtime,
    # silently failing every shot that uses it. Compile them all here.
    for expr in re.findall(r'"([^"\n]*d(?:\[|\.get\()[^"\n]*)"', render):
        if "$" in expr or ";" in expr:  # shell substitution, or a helper's own python
            continue
        try:
            compile(expr, "<render want>", "eval")
        except SyntaxError as exc:
            raise AssertionError(
                f"render want is not valid Python: {expr!r} ({exc})"
            ) from exc
