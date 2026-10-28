import sys
from pathlib import Path

# bridge/ is not a package — the bridge runs as a script with bridge/ on sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bridge"))
