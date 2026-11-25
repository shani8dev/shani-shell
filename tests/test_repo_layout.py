"""The repo holds the project; everything a run writes goes to out/ (ignored).

Stray output directories at the top (render-out/, renderone/: 150 MB of PNGs
from ad-hoc renders, and a root-owned `2/` from a mistyped redirect) were one
`git add .` away from being committed. Two checks:

- nothing at the top level that is neither tracked nor a known ignored place
- the harnesses write only under /work/out (or /tmp) inside the container
"""
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
# ignored on purpose (.gitignore): run output and tool caches
IGNORED_OK = {"out", "__pycache__", ".pytest_cache", ".ruff_cache", ".serena", ".codegraph", ".git"}


def tracked_top_level():
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "ls-files"], capture_output=True,
                             text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        pytest.skip("not a git checkout")
    return {line.split("/", 1)[0] for line in out.splitlines() if line}


def test_no_stray_entries_at_the_top():
    tracked = tracked_top_level()
    stray = sorted(p.name for p in ROOT.iterdir()
                   if p.name not in tracked and p.name not in IGNORED_OK)
    assert not stray, (
        f"not part of the project: {stray}. Run output belongs in out/ "
        "(sh dev/check.sh writes there); move it or add it to git on purpose.")


def test_ignore_covers_the_output_and_cache_places():
    ignore = (ROOT / ".gitignore").read_text().split()
    for place in ("out/", "__pycache__/", ".pytest_cache/", ".ruff_cache/", ".serena/", ".codegraph/"):
        assert place in ignore, place


# /work/<top> paths a harness writes to inside the container: grim/mkdir/tee/>
# targets, and the destination (last argument) of cp/mv
WRITE = re.compile(r"(?:grim|mkdir -p|>|tee)\s+\"?(/work/[A-Za-z0-9_.-]+)")
COPY = re.compile(r"\b(?:cp|mv)\b[^|;&\n]*\s\"?(/work/[A-Za-z0-9_.-]+)[^\s|;&]*\"?\s*(?:$|[|;&])", re.M)
# deliberate writes into tracked places, with the reason
ALLOWED = {
    # restages the README's two pictures (docs/showcase-*.png are tracked)
    ("showcase.sh", "/work/docs"),
}


@pytest.mark.parametrize("script", sorted(p.name for p in (ROOT / "dev").glob("*.sh")))
def test_harnesses_write_only_into_out(script):
    src = (ROOT / "dev" / script).read_text()
    targets = {m.group(1) for m in WRITE.finditer(src)} | {m.group(1) for m in COPY.finditer(src)}
    bad = sorted(t for t in targets if t != "/work/out" and (script, t) not in ALLOWED)
    assert not bad, f"dev/{script} writes outside /work/out: {bad}"


def test_render_keeps_a_given_directory_inside_out():
    src = (ROOT / "dev" / "render.sh").read_text()
    assert "in_out()" in src
    assert 'OUTDIR="$1"' not in src and 'OUTDIR="${5:-' not in src


# ---- one set of harness helpers ------------------------------------------------
HELPERS = ("result", "st", "q", "ipc", "ipc_line", "waitfor", "shot", "settings", "settings_merge")


def test_harness_helpers_are_defined_once():
    # the copies had drifted: waitfor's second argument was seconds in the suite
    # and half-second ticks in the render; the suite's waitfor clobbered `i`
    rx = re.compile(r"^\s*(%s)\(\)\s*\{" % "|".join(HELPERS), re.M)
    owners = {}
    for p in [*sorted((ROOT / "dev").glob("*.sh")), *sorted((ROOT / "dev" / "shell-parts").glob("*.sh"))]:
        for m in rx.finditer(p.read_text()):
            owners.setdefault(m.group(1), []).append(p.relative_to(ROOT).as_posix())
    strays = {k: v for k, v in owners.items() if v != ["dev/harness.sh"]}
    assert not strays, f"harness helpers defined outside dev/harness.sh: {strays}"
    assert set(owners) == set(HELPERS)
