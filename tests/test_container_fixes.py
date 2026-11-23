"""Pass-22 container fixes, as static invariants on the sources they touch:

1. the destructive prune needs the same two-tap confirm as a container delete;
2. an armed delete confirmation is cleared on a tab switch and times out;
3. an own-name D-Bus row is removed with --no-own-name, not --no-talk-name;
4. a toolbox app exported to the menu can be exported back out again.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text()


def test_prune_needs_a_second_click():
    s = read("shani/Modules/Containers/ContainersWindow.qml")
    assert 'win.removing === "__prune__"' in s
    assert 'Tr.t("Click again: remove unused images")' in s
    assert 'else win.removing = "__prune__"' in s
    assert 'win.run(["prune"]' in s


def test_delete_confirmation_expires():
    s = read("shani/Modules/Containers/ContainersWindow.qml")
    assert 'onTabChanged: win.removing = ""' in s
    assert 'onRemovingChanged: if (removing !== "") confirmTimer.restart()' in s
    assert "Timer { id: confirmTimer" in s
    assert 'onTriggered: win.removing = ""' in s


def test_own_bus_names_are_removed_with_the_own_flag():
    s = read("shani/Modules/Settings/SettingsAppPermissions.qml")
    assert "function busNoFlag(system, value)" in s
    assert 'value === "own" ? "own-name" : "talk-name"' in s
    assert "page.busNoFlag(false, page.perms.session[modelData])" in s
    assert "page.busNoFlag(true, page.perms.system[modelData])" in s


def test_exported_app_can_be_unexported():
    b = read("bridge/containers.py")
    s = read("shani/Modules/Containers/ContainersWindow.qml")
    assert 'cmd in ("box-export", "box-unexport")' in b
    assert 'tail = ["--delete"] if unexport else []' in b
    assert 'win.run(["box-unexport", box, id]' in s
    assert 'Tr.t("Remove from menu")' in s
