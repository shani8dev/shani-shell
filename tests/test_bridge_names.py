"""No bridge script may share a name with a Python standard-library module: the
bridges run from one folder, which is first on each one's import path, so a
bridge/secrets.py once made serve.py's `import secrets` load it instead of the
standard library's (and its secret links failed)."""
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parent.parent / "bridge"


def test_no_bridge_shadows_the_standard_library():
    clash = sorted(p.name for p in BRIDGE.glob("*.py") if p.stem in sys.stdlib_module_names)
    assert not clash, clash
