import sys
from pathlib import Path

# bridge/ is not a package — the bridge runs as a script with bridge/ on sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bridge"))

# Never the machine's real /dev/uinput: the gamepad bridge would make a live mouse
# on the desktop running the tests (bridge/gamepad.py Pointer). A test that wants
# the pointer passes its own node.
import os  # noqa: E402
os.environ["SHANI_UINPUT"] = "/nonexistent/uinput"
