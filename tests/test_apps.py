"""The shell's apps: one table (bin/shani's APPS), and what has to agree with it."""
import importlib.machinery
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def apps():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin/shani"))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader("shani_cli", loader))
    loader.exec_module(module)
    return module.APPS


def test_window_titles_map_to_the_same_ids_as_the_table():
    """Services/ShellApps.js turns a window's title into its desktop entry id;
    a name changed in one place only leaves that app as a nameless
    "org.quickshell" in the dock and the switcher."""
    text = (ROOT / "shani/Services/ShellApps.js").read_text()
    ids = json.loads(re.search(r"var ids = (\{.*?\});", text, re.S).group(1))
    assert ids == {spec[1]: spec[0] for spec in apps().values()}


def test_every_app_window_carries_a_name_from_the_table():
    names = {spec[1] for spec in apps().values()}
    wrong = {}
    for path in (ROOT / "shani").rglob("*.qml"):
        for name in re.findall(r'^\s*appName: "([^"]*)"', path.read_text(), re.M):
            if name not in names:
                wrong[path.name] = name
    assert wrong == {}


def test_every_shell_window_has_the_shells_header():
    """Qt's own window decoration is a white Adwaita bar that ignores the
    theme. It is off for the shell's process, so a window that is not an
    AppWindow would have no header at all - and the service and the test
    session must both turn it off."""
    bare = [p.name for p in (ROOT / "shani").rglob("*.qml")
            if re.search(r"^FloatingWindow \{", p.read_text(), re.M) and p.name != "AppWindow.qml"]
    assert bare == []
    for unit in ("data/systemd/shani-shell.service", "dev/session.sh"):
        assert "QT_WAYLAND_DISABLE_WINDOWDECORATION=1" in (ROOT / unit).read_text(), unit
