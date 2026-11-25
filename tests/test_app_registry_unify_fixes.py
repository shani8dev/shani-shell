"""One static cross-check of the app registry, so future drift fails fast.

One table (bin/shani's APPS) feeds the desktop entries and `shani app`, the
dock/switcher ids in ShellApps.js, the window titles in Modules and the shell's
IPC. A name changed in one place only leaves an app that cannot be started or
titled, and neither fails loudly. This reads the files as text - no running
shell - and refuses the drift.
"""

import importlib.machinery
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _apps():
    loader = importlib.machinery.SourceFileLoader("shani_cli", str(ROOT / "bin/shani"))
    module = importlib.util.module_from_spec(
        importlib.util.spec_from_loader("shani_cli", loader)
    )
    loader.exec_module(module)
    return module.APPS


def test_apps_titles_shellapps_ids_and_window_names_agree():
    """APPS titles <-> ShellApps ids <-> every Module's appName literal, plus the
    IPC each APPS entry calls. Keeps the four lists one list."""
    apps = _apps()
    titles = {spec[1]: spec[0] for spec in apps.values()}

    text = (ROOT / "shani/Services/ShellApps.js").read_text(encoding="utf-8")
    ids = json.loads(re.search(r"var ids = (\{.*?\});", text, re.S).group(1))
    assert ids == titles, (
        f"ShellApps.js drift: missing={sorted(set(titles) - set(ids))}, "
        f"extra={sorted(set(ids) - set(titles))}, "
        f"wrong id={[k for k in ids if k in titles and ids[k] != titles[k]]}"
    )

    names = set()
    for path in (ROOT / "shani/Modules").rglob("*.qml"):
        names.update(
            re.findall(
                r'^\s*appName:\s*(?:Tr\.t\(\s*)?"([^"]*)"',
                path.read_text(encoding="utf-8"),
                re.M,
            )
        )
    assert names <= set(titles), (
        f"window appName with no APPS entry/ShellApps id: {sorted(names - set(titles))}"
    )

    shell = (ROOT / "shani/shell.qml").read_text(encoding="utf-8")
    start = shell.index("IpcHandler {")
    end = shell.index("\n    }", start)
    funcs = set(re.findall(r"^\s*function\s+(\w+)\s*\(", shell[start:end], re.M))
    missing = [
        (name, call[0])
        for name, spec in apps.items()
        for call in (spec[6], spec[7])
        if isinstance(call, list) and call and call[0] not in funcs
    ]
    assert not missing, f"APPS entries call IPC the shell does not declare: {missing}"
