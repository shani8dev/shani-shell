"""A harness file that stands in for one feature's tools must not redirect what
another feature reads. dev/fake-system-env.sh once set SHANI_PAM_DIR - the lock
screen's own override - for the Sign-in page, and every dev session's lock
screen could no longer unlock; it also pointed the Software store's flatpak and
snap at the System pages' stand-ins. Its variables are the System pages' own:
SHANI_SYSTEM_*, or ones nothing outside bridge/system_*.py reads."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_system_harness_variables_are_its_own():
    env = (ROOT / "dev/fake-system-env.sh").read_text()
    names = sorted(set(re.findall(r"\b(SHANI_[A-Z0-9_]+)=", env)))
    assert names, "the harness sets nothing?"
    clashes = {}
    for name in names:
        if name.startswith("SHANI_SYSTEM_"):
            continue
        users = [
            str(p.relative_to(ROOT))
            for p in list((ROOT / "shani").rglob("*.qml")) + list((ROOT / "shani").rglob("*.js")) + list((ROOT / "bridge").rglob("*.py"))
            if not p.name.startswith("system_") and re.search(r"\b%s\b" % name, p.read_text(errors="ignore"))
        ]
        if users:
            clashes[name] = users
    assert clashes == {}, "the System pages' harness redirects what other features read"
