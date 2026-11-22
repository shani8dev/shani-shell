"""Static checks for the 17th-pass window-menu / closeApps fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVC = (ROOT / "shani/Services/WindowLayouts.qml").read_text()
MENU = (ROOT / "shani/Modules/WindowMenu/WindowMenu.qml").read_text()
UI = (ROOT / "shani/Common/Ui.qml").read_text()


def test_edge_snap_wired_to_menu():
    # the service accepts left/right; the menu must actually call it
    assert 'edge === "left" || edge === "right"' in SVC
    assert 'WindowLayouts.snapToEdge("left")' in MENU
    assert 'WindowLayouts.snapToEdge("right")' in MENU


def test_swap_column_entries():
    assert 'Niri.action("swap-column-left")' in MENU
    assert 'Niri.action("swap-column-right")' in MENU
    for action in ("swap-column-left", "swap-column-right"):
        line = next(l for l in MENU.splitlines() if f'"{action}"' in l)
        assert 'Niri.action("focus-window", "--id", target.id)' in line


def test_closeapps_missing_flags():
    body = UI[UI.index("function closeApps()") :].split("closedApps()")[0]
    for flag in ("mail", "feeds", "calls", "messages", "backup"):
        assert f"{flag} = false" in body


def test_rows_layout_is_not_a_noop():
    branch = SVC[SVC.index("else if (layout.rows > 1)") :]
    branch = branch[: branch.index("}")]
    assert 'Niri.action("set-column-width", "100%")' in branch
    assert "move-window-down" not in branch and "move-window-up" not in branch
    # the top-of-function comment documents the niri vertical-split limit
    assert "cannot split a column" in SVC
