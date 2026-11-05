"""Settings > Keyboard shortcuts reads niri's binds (shani/Modules/Settings/NiriBinds.js),
run in node against the session's config and the one the desktop package ships."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
JS = ROOT / "shani/Modules/Settings/NiriBinds.js"
CONFIGS = [ROOT / "dev/niri/session.kdl", ROOT.parent / "shani-pkgbuilds/shani-desktop-niri/etc/niri/config.kdl"]
node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def parse(text):
    prog = JS.read_text().replace(".pragma library", "") + \
        "\nprocess.stdout.write(JSON.stringify(parse(require('fs').readFileSync(0, 'utf8'))));"
    return json.loads(subprocess.run([node, "-e", prog], input=text, capture_output=True, text=True, check=True).stdout)


@pytest.mark.parametrize("config", CONFIGS, ids=lambda p: p.parent.name + "/" + p.name)
def test_the_named_binds_are_listed(config):
    if not config.exists():
        pytest.skip(f"{config} is not here")
    titles = {b["title"] for b in parse(config.read_text())}
    assert {"Clipboard history", "Minimise", "Launcher"} <= titles, sorted(titles)


def test_hidden_and_unnamed_commands_are_left_out():
    binds = parse('binds {\n    Mod+A hotkey-overlay-title="" { spawn "x"; }\n    Mod+B { spawn "y"; }\n'
                  '    Mod+C repeat=false { close-window; }\n    Mod+D hotkey-overlay-title="Files" { spawn "nautilus"; }\n}\n')
    assert binds == [{"key": "Mod+C", "title": "Close window"}, {"key": "Mod+D", "title": "Files"}]
