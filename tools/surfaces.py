#!/usr/bin/env python3
"""Every surface the shell can show, from the code, and where each is photographed.

The surface list is read from shani/shell.qml (what it instantiates, directly,
in Variants or behind a LazyLoader, with the condition that gates it) - not from
the harnesses, so a surface nobody wrote a capture for still shows up as missing.
Evidence is read from every harness: dev/render.sh captures and the shell
suite's shots (dev/shell-test.sh, dev/shell-parts/*.sh).

dev/surfaces.tsv is the one catalog that ties them together: one row per
surface - `surface<TAB>captures<TAB>note` - where captures are render/shot
names separated by spaces, or `-` with the reason the surface cannot be
photographed in the nested session.

  tools/surfaces.py list        every surface and its gate
  tools/surfaces.py check       catalog vs code vs harnesses; exit 1 on a gap
  tools/surfaces.py missing     surfaces with no capture yet (and their gates)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "shani" / "shell.qml"
CATALOG = ROOT / "dev" / "surfaces.tsv"

LAZY = re.compile(r'LazyLoader\s*\{\s*(?:id:\s*\w+;\s*)?active:\s*(.+?);\s*'
                  r'(?:source:\s*"Modules/(?:[\w]+/)*(\w+)\.qml"|(\w+)\s*\{\s*\})')
VARIANTS = re.compile(r'Variants\s*\{\s*model:[^;]+;\s*(\w+)\s*\{\s*\}')
# `Type {}` or `Type { id: x }`, anywhere on a top-level line (two can share one)
BARE = re.compile(r'(?<![\w.])([A-Z]\w+)\s*\{\s*(?:id:\s*\w+\s*)?\}')
# a non-visual type instantiated at the top of shell.qml is not a surface
NOT_SURFACES = {"IpcHandler", "Connections", "Timer", "Process", "Scope", "ShellRoot", "Item",
                "Binding", "Shortcut"}


def surfaces():
    """{name: gate} for everything shell.qml puts on screen ("" = always loaded)."""
    src = SHELL.read_text()
    out = {}
    for m in LAZY.finditer(src):
        out[m.group(2) or m.group(3)] = m.group(1).strip()
    for m in VARIANTS.finditer(src):
        out.setdefault(m.group(1), "per screen")
    for line in src.splitlines():
        if not line.startswith("    ") or line.startswith("     "):
            continue                       # top level of ShellRoot only
        for m in BARE.finditer(line):
            if m.group(1) not in NOT_SURFACES:
                out.setdefault(m.group(1), "")
    return out


def app_names():
    """bin/shani's APPS table: render.sh photographs each as app-<name>."""
    import importlib.machinery
    import importlib.util
    loader = importlib.machinery.SourceFileLoader("_shani_cli_surfaces", str(ROOT / "bin" / "shani"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    # only windows: an entry whose state key (field 8) is None is an action
    return [name for name, spec in mod.APPS.items() if spec[8] is not None]


def expand(text, pattern):
    """Capture names in `text`; `prefix-$var` is expanded from the nearest
    `for var in a b c` above it."""
    out = set()
    for m in re.finditer(pattern, text):
        name = m.group(1)
        if "$" not in name:
            out.add(name)
            continue
        var = re.search(r"\$\{?(\w+)", name).group(1)
        loops = list(re.finditer(r"for %s in ([^;\n$(]+);" % var, text[:m.start()]))
        if loops:
            for word in loops[-1].group(1).split():
                out.add(re.sub(r"\$\{?%s\}?" % var, word, name))
    return out


def captures():
    """Every capture name any harness takes: render scenes and suite shots."""
    render = (ROOT / "dev" / "render.sh").read_text()
    names = expand(render, r'\bcapture(?:_current)?\s+"?([\w${}-]+)')
    names |= {"app-" + a for a in app_names()}
    # every other harness: the shell suite and its parts, greeter, setup, polkit...
    others = [p for p in sorted((ROOT / "dev").glob("*.sh")) if p.name != "render.sh"]
    for p in [*others, *sorted((ROOT / "dev" / "shell-parts").glob("*.sh"))]:
        text = p.read_text()
        names |= expand(text, r'\bshot\s+"?([\w${}.-]+)')
        names |= expand(text, r'\bgrim\b[^\n]*?/([\w${}.-]+)\.png')
    return names


def catalog():
    rows = {}
    if not CATALOG.exists():
        return rows
    for line in CATALOG.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        name, caps = parts[0], (parts[1] if len(parts) > 1 else "")
        note = parts[2] if len(parts) > 2 else ""
        rows[name] = ([] if caps.strip() in ("", "-") else caps.split(), note)
    return rows


def check():
    code, have, cat = surfaces(), captures(), catalog()
    problems = []
    for name in sorted(set(code) - set(cat)):
        problems.append(f"not in dev/surfaces.tsv: {name} (gate: {code[name] or 'always'})")
    for name in sorted(set(cat) - set(code)):
        problems.append(f"in dev/surfaces.tsv but shell.qml no longer loads it: {name}")
    for name, (caps, note) in sorted(cat.items()):
        if not caps and not note:
            problems.append(f"{name}: no capture and no reason it cannot be photographed")
        for c in caps:
            if c not in have:
                problems.append(f"{name}: capture '{c}' is not taken by any harness")
    return problems


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "check"
    if cmd == "list":
        for name, gate in sorted(surfaces().items()):
            print(f"{name:28} {gate or 'always'}")
        return 0
    if cmd == "missing":
        code, cat = surfaces(), catalog()
        for name, gate in sorted(code.items()):
            caps = cat.get(name, ([], ""))[0]
            if not caps and not cat.get(name, ([], ""))[1]:
                print(f"{name:28} {gate or 'always'}")
        return 0
    if cmd == "check":
        problems = check()
        for p in problems:
            print(p)
        print(f"{len(surfaces())} surfaces, {len(problems)} problem(s)")
        return 1 if problems else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
