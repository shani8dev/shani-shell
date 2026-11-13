#!/usr/bin/env python3
"""appmenu - an app's own menu bar, read over AT-SPI, for the window menu.

    appmenu.py menu PID [TITLE]     the menu bar of the app with this process id
                                    (the window whose accessible name is TITLE first):
                                    {"menus": [{"label", "path", "enabled", "checked",
                                    "shortcut", "items": [...]}, ...]} - or {"menus": []}
    appmenu.py activate PID PATH [TITLE]
                                    click the item at PATH ("0/3": the fourth item of
                                    the first menu) - prints {"done": true} or {"error"}

niri has no app-menu protocol (KWin's org_kde_kwin_appmenu is KWin's alone) and
GTK 4 exports no menu over D-Bus, but an app's accessibility tree has its menu
bar - the same tree a screen reader walks (the approach noctalia-appmenu takes on
niri). GTK 3 and Qt (with QT_LINUX_ACCESSIBILITY_ALWAYS_ON) expose theirs whole;
a GTK 4 popover menu bar is empty until opened, and Firefox's fill only once
opened, so those come back with no menus and the window menu offers the app's
desktop actions instead. Nothing is cached: the menu is read when the window
menu opens, so it is never stale.
"""
from __future__ import annotations

import json
import sys

try:
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi
except (ImportError, ValueError):  # pragma: no cover - at-spi2-core is in the image
    Atspi = None

MAX_NODES = 4000          # a menu bar is near the top; a big document is not walked
MAX_DEPTH = 4             # menus inside menus inside menus, and no further

ITEM_ROLES = {"menu", "menu item", "check menu item", "radio menu item", "separator", "tearoff menu item"}


def role(node) -> str:
    try:
        return node.get_role_name() or ""
    except Exception:  # noqa: BLE001 - a dying app: no role, nothing to show
        return ""


def children(node) -> list:
    out = []
    try:
        n = node.get_child_count()
    except Exception:  # noqa: BLE001
        return out
    for i in range(n):
        try:
            c = node.get_child_at_index(i)
        except Exception:  # noqa: BLE001
            c = None
        if c is not None:
            out.append(c)
    return out


def find_app(pid: int):
    desktop = Atspi.get_desktop(0)
    for app in children(desktop):
        try:
            if app.get_process_id() == pid:
                return app
        except Exception:  # noqa: BLE001
            continue
    return None


def find_menubar(root):
    """The first menu bar under root, breadth first, within MAX_NODES."""
    queue, seen = [root], 0
    while queue and seen < MAX_NODES:
        node = queue.pop(0)
        seen += 1
        if role(node) == "menu bar":
            return node
        queue.extend(children(node))
    return None


def frames(app, title: str) -> list:
    """The app's windows, the one called TITLE first."""
    wins = children(app)
    if title:
        wins.sort(key=lambda w: 0 if (w.get_name() or "") == title else 1)
    return wins


def states(node) -> set:
    try:
        ss = node.get_state_set()
        return {s for s in (Atspi.StateType.ENABLED, Atspi.StateType.SENSITIVE, Atspi.StateType.CHECKED,
                            Atspi.StateType.CHECKABLE) if ss.contains(s)}
    except Exception:  # noqa: BLE001
        return set()


def shortcut(node) -> str:
    """The item's accelerator as a person reads it: <Control>s -> Ctrl+S."""
    try:
        act = node.get_action_iface()
        raw = act.get_key_binding(0) if act and act.get_n_actions() > 0 else ""
    except Exception:  # noqa: BLE001
        raw = ""
    # GTK gives "mnemonic;sequence;accelerator", Qt the accelerator alone
    accel = raw.split(";")[-1] if raw else ""
    if not accel:
        return ""
    for a, b in (("<Primary>", "Ctrl+"), ("<Control>", "Ctrl+"), ("<Ctrl>", "Ctrl+"), ("<Shift>", "Shift+"),
                 ("<Alt>", "Alt+"), ("<Super>", "Super+")):
        accel = accel.replace(a, b)
    head, _, key = accel.rpartition("+")
    return (head + "+" if head else "") + (key.upper() if len(key) == 1 else key)


def serialize(node, path: str, depth: int) -> list:
    out = []
    for i, c in enumerate(children(node)):
        r = role(c)
        if r not in ITEM_ROLES:
            continue
        p = f"{path}/{i}" if path else str(i)
        if r == "separator":
            out.append({"separator": True, "path": p})
            continue
        st = states(c)
        item = {"label": (c.get_name() or "").replace("_", ""), "path": p,
                "enabled": Atspi.StateType.SENSITIVE in st or Atspi.StateType.ENABLED in st,
                "checked": Atspi.StateType.CHECKED in st, "shortcut": shortcut(c)}
        if r == "menu" and depth < MAX_DEPTH:
            item["items"] = serialize(c, p, depth + 1)
        if item["label"] or item.get("items"):
            out.append(item)
    return out


def menu(pid: int, title: str = "") -> dict:
    app = find_app(pid)
    if app is None:
        return {"menus": [], "why": "the app is not on the accessibility bus"}
    for frame in frames(app, title):
        bar = find_menubar(frame)
        if bar is not None:
            menus = serialize(bar, "", 0)
            if any(m.get("items") for m in menus):
                return {"menus": menus, "app": app.get_name() or ""}
    return {"menus": [], "why": "no menu bar it shows while closed"}


def activate(pid: int, path: str, title: str = "") -> dict:
    app = find_app(pid)
    if app is None:
        return {"error": "the app is gone"}
    for frame in frames(app, title):
        bar = find_menubar(frame)
        if bar is None:
            continue
        node = bar
        try:
            for step in path.split("/"):
                node = children(node)[int(step)]
        except (IndexError, ValueError):
            continue
        act = node.get_action_iface()
        if act is None or act.get_n_actions() == 0:
            return {"error": "that item cannot be pressed"}
        act.do_action(0)
        return {"done": True, "label": node.get_name() or ""}
    return {"error": "that item is no longer in the menu"}


def main(argv: list[str]) -> int:
    if Atspi is None:
        print(json.dumps({"menus": [], "why": "AT-SPI (at-spi2-core) is not installed"}))
        return 0
    if len(argv) >= 3 and argv[1] == "menu":
        print(json.dumps(menu(int(argv[2]), argv[3] if len(argv) > 3 else "")))
        return 0
    if len(argv) >= 4 and argv[1] == "activate":
        print(json.dumps(activate(int(argv[2]), argv[3], argv[4] if len(argv) > 4 else "")))
        return 0
    print("usage: appmenu.py menu PID [TITLE] | activate PID PATH [TITLE]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
