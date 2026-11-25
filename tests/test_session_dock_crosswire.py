"""Cross-wiring wave 3's named sessions and Speed Dial into Launcher and Dock.

Static hooks: the launcher must offer session save/restore and Speed Dial places,
the dock's app menu must open a place, and neither may need a new IPC hook in the
contested shell.qml (or a new launcher surface). Pure rules: the very same JS the
services use is run in node for the name checks, canonical dedupe and the flat
place list the two surfaces read.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHANI = ROOT / "shani"
SESSIONS_QML = SHANI / "Services/Sessions.qml"
SESSIONS_JS = SHANI / "Services/Sessions.js"
SPEEDDIAL_QML = SHANI / "Services/SpeedDial.qml"
SPEEDDIAL_JS = SHANI / "Services/SpeedDial.js"
LAUNCHER_ACTIONS = SHANI / "Modules/Launcher/LauncherActions.qml"
DOCK = SHANI / "Modules/Dock/Dock.qml"
SETTINGS_STARTUP = SHANI / "Modules/Settings/SettingsStartup.qml"
SHELL = SHANI / "shell.qml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


node = shutil.which("node")
pytestmark = pytest.mark.skipif(node is None, reason="node is not installed")


def call(logic: Path, expr):
    prog = (
        logic.read_text(encoding="utf-8").replace(".pragma library", "")
        + "\nprocess.stdout.write(JSON.stringify(%s));" % expr
    )
    got = subprocess.run([node, "-e", prog], capture_output=True, text=True, check=True)
    return json.loads(got.stdout)


# ---- static hooks -----------------------------------------------------------


def test_services_keep_their_existing_public_api():
    q = read(SESSIONS_QML)
    for fn in [
        "function list(",
        "function validName(",
        "function saveCurrent(",
        "function restore(",
    ]:
        assert fn in q, fn
    assert 'import "Sessions.js" as Logic' in q
    s = read(SPEEDDIAL_QML)
    for fn in ["function sections(", "function entries(", "function open("]:
        assert fn in s, fn
    assert 'import "SpeedDial.js" as Logic' in s


def test_speed_dial_exposes_one_read_only_flat_hook():
    assert "function places() { return Logic.places(root.data, root.home); }" in read(
        SPEEDDIAL_QML
    )
    assert "function places(data, home, limit)" in read(SPEEDDIAL_JS)
    # the hook reads state, it never writes the store or shows a surface
    places = read(SPEEDDIAL_QML).split("function places()", 1)[1].split("\n", 1)[0]
    assert "commit(" not in places and "Ui." not in places


def test_launcher_wires_both_session_actions_without_new_ipc():
    acts = read(LAUNCHER_ACTIONS)
    assert 'Tr.t("Save this session…")' in acts
    assert 'Tr.t("Restore session…")' in acts
    # the save form already lives in Settings > Default apps > Sessions
    assert 'run: () => launcher.openSettings("apps")' in acts
    assert "Sessions.saveCurrent(sessionName.text)" in read(SETTINGS_STARTUP)
    # a saved set also gets a direct restore action from the launcher
    assert "Sessions.list().slice(0, 8).map(s =>" in acts
    assert "Sessions.restore(s.name)" in acts
    assert 'Tr.t("Restore session %1").arg(s.name)' in acts
    # no new shell.qml IpcHandler hook: these call the services directly
    assert "sessionSave(" not in acts and "sessionRestore(" not in acts
    assert "ipc" not in acts.lower()


def test_launcher_search_finds_speed_dial_places():
    acts = read(LAUNCHER_ACTIONS)
    assert "SpeedDial.places().map(p =>" in acts
    assert "SpeedDial.open(p.path)" in acts
    assert "import qs.Services" in acts


def test_dock_context_menu_lists_and_opens_speed_dial_places():
    dock = read(DOCK)
    assert 'Tr.t("Open Speed Dial place…")' in dock
    assert "SpeedDial.places().length > 0" in dock
    assert "win.speedDialOpen ? SpeedDial.places().slice(0, 10)" in dock
    assert "SpeedDial.open(p.path)" in dock
    assert "keep: true" in dock
    assert "property bool speedDialOpen: false" in dock
    # the submenu never survives a different open menu
    assert (
        "function setMenu(index, anchor) {\n        win.speedDialOpen = false;" in dock
    )


def test_dock_menu_keeps_its_height_focus_and_accessibility():
    dock = read(DOCK)
    # a taller expanded menu still fits the dock's intellihide region
    assert "Math.max(230, menuHeight + 40)" in dock
    assert "onHeightChanged: if (visible) win.menuHeight = height" in dock
    assert "Accessible.role: Accessible.MenuItem" in dock
    assert "Accessible.name: modelData.label" in dock
    assert "KeyFocus { radius: Theme.px(8);" in dock
    assert "win.setMenu(-1); tileFocus.forceActiveFocus(Qt.TabFocusReason);" in dock
    # no opaque card for the new rows: they reuse the menu row's Theme colours
    block = dock.split('Tr.t("Open Speed Dial place…")', 1)[1].split(
        "...cell.modelData.entry ?", 1
    )[0]
    assert "color: Theme.surface" not in block
    assert "Tr.t(" in block and "SpeedDial.places()" in block


def test_contested_surfaces_need_no_new_hook():
    shell = read(SHELL)
    # the existing session IPC is enough for tests and scripts; the new wires
    # are QML-to-QML and do not add a shell.qml or Launcher.qml surface.
    assert "function sessionSave(name: string)" in shell
    assert "function sessionRestore(name: string)" in shell
    for acts in [read(LAUNCHER_ACTIONS), read(DOCK)]:
        assert "sessionSave(" not in acts and "sessionRestore(" not in acts


# ---- pure rules, run in node ------------------------------------------------


def sess(expr):
    return call(SESSIONS_JS, expr)


def dial(expr):
    return call(SPEEDDIAL_JS, expr)


def test_session_names_are_validated_before_any_action():
    assert sess('cleanName("Focus work")') == "Focus work"
    assert sess('cleanName("  Work  ")') == "Work"
    for bad in [
        "",
        "   ",
        "../work",
        "one/two",
        "one\\two",
        "__proto__",
        "toString",
        "a" * 61,
    ]:
        assert sess("cleanName(%s)" % json.dumps(bad)) == "", bad
    got = sess('put({}, "Focus", ["app"], ["~/docs"], "2026-11-25")')
    assert list(got) == ["Focus"]
    assert got["Focus"]["paths"] == ["~/docs"]


def test_restore_actions_come_from_the_sessions_list():
    data = sess('put({}, "Work", ["a", "b"], ["/docs"], "2026-11-25")')
    data = sess(
        "put(%s, %s, [], [], %s)"
        % (json.dumps(data), json.dumps("Reading"), json.dumps("2026-11-24"))
    )
    targets = sess(
        "toList(%s).slice(0, 8).map(s => ({ name: s.name, restore: s.name }))"
        % json.dumps(data)
    )
    assert targets == [
        {"name": "Work", "restore": "Work"},
        {"name": "Reading", "restore": "Reading"},
    ]


def test_speed_dial_places_are_canonical_and_deduped():
    data = {
        "sections": [
            {
                "name": "Work",
                "entries": [
                    {"name": "Docs", "path": "/home/me/./docs/", "pinnedAt": 20},
                    {"name": "Dup", "path": "~/docs", "pinnedAt": 99},
                ],
            },
            {
                "name": "Home",
                "entries": [
                    {"name": "Again", "path": "/home/me/docs", "pinnedAt": 100},
                    {"name": "Music", "path": "~/music", "pinnedAt": 10},
                ],
            },
        ]
    }
    places = dial("places(%s, %s)" % (json.dumps(data), json.dumps("/home/me")))
    # one canonical path, kept once (the first pin wins), newest pins first
    assert [p["path"] for p in places] == ["/home/me/docs", "/home/me/music"]
    assert places[0]["name"] == "Docs" and places[0]["section"] == "Work"
    assert len([p for p in places if p["path"] == "/home/me/docs"]) == 1


def test_speed_dial_places_are_capped_for_the_dock_menu():
    entries = [
        {"name": "p%02d" % i, "path": "/p/%d" % i, "pinnedAt": i} for i in range(30)
    ]
    data = {"sections": [{"name": "Many", "entries": entries}]}
    assert len(dial('places(%s, "", 10)' % json.dumps(data))) == 10
    assert len(dial('places(%s, "")' % json.dumps(data))) == 18
