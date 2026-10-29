import importlib.util
import json
import subprocess
import sys
from pathlib import Path

PATH = Path(__file__).parent.parent / "bridge" / "appfilter.py"
spec = importlib.util.spec_from_file_location("appfilter", PATH)
af = importlib.util.module_from_spec(spec)
spec.loader.exec_module(af)


class App:
    def __init__(self, i): self.i = i
    def get_id(self): return self.i


class Filter:
    def __init__(self, blocked): self.blocked = blocked
    def is_appinfo_allowed(self, a): return a.get_id() not in self.blocked


def test_blocked_ids_are_desktop_ids_without_suffix():
    apps = [App("foot.desktop"), App("foot-server.desktop"), App("org.gnome.Nautilus.desktop")]
    assert af.blocked_ids(Filter({"foot.desktop", "foot-server.desktop"}), apps) == ["foot", "foot-server"]


def test_without_malcontent_says_so():
    # the dev machine has no Malcontent typelib (or no system bus): never blocks anything
    out = subprocess.run([sys.executable, str(PATH)], capture_output=True, text=True, timeout=20).stdout
    d = json.loads(out.splitlines()[0])
    assert d["blocked"] == [] and "available" in d
