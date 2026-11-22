#!/usr/bin/env python3
"""appmenu - an app's own menu bar, for the window menu.

    appmenu.py menu PID [TITLE] [APP_ID]
                                    the menu bar of the app with this process id
                                    (the window whose accessible name is TITLE first):
                                    {"menus": [{"label", "path", "enabled", "checked",
                                    "shortcut", "items": [...]}, ...]}
    appmenu.py activate PID PATH [TITLE] [APP_ID]
                                    click the item at PATH ("0/3": the fourth item of
                                    the first menu) - prints {"done": true} or {"error"}

The app's D-Bus menus are read first (com.canonical.dbusmenu via the AppMenu
Registrar, then org.gtk.Menus/org.gtk.Actions), and the accessibility tree is
the fallback. Nothing is cached: the menu is read when the window menu opens,
so it is never stale and activation re-resolves the item before pressing it.
"""

from __future__ import annotations

import json
import re
import sys

try:
    import gi

    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi
except (ImportError, ValueError):  # pragma: no cover - at-spi2-core is in the image
    Atspi = None

try:
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
except (ImportError, ValueError):  # pragma: no cover - a missing bus just falls back
    dbus = None
    DBusGMainLoop = None

MAX_NODES = 4000  # a menu bar is near the top; a big document is not walked
MAX_DEPTH = 4  # menus inside menus inside menus, and no further
MAX_MENU_DEPTH = 8  # guard the D-Bus trees against a cyclic/oversized reply

ITEM_ROLES = {
    "menu",
    "menu item",
    "check menu item",
    "radio menu item",
    "separator",
    "tearoff menu item",
}

REG_NAME = "com.canonical.AppMenu.Registrar"
REG_PATH = "/com/canonical/AppMenu/Registrar"
LABEL_SEP = "  »  "
T = 2  # D-Bus timeout, seconds


# --------------------------------------------------------------------------- AT-SPI


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
        return {
            s
            for s in (
                Atspi.StateType.ENABLED,
                Atspi.StateType.SENSITIVE,
                Atspi.StateType.CHECKED,
                Atspi.StateType.CHECKABLE,
            )
            if ss.contains(s)
        }
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
    for a, b in (
        ("<Primary>", "Ctrl+"),
        ("<Control>", "Ctrl+"),
        ("<Ctrl>", "Ctrl+"),
        ("<Shift>", "Shift+"),
        ("<Alt>", "Alt+"),
        ("<Super>", "Super+"),
    ):
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
        item = {
            "label": (c.get_name() or "").replace("_", ""),
            "path": p,
            "enabled": Atspi.StateType.SENSITIVE in st or Atspi.StateType.ENABLED in st,
            "checked": Atspi.StateType.CHECKED in st,
            "shortcut": shortcut(c),
        }
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


# --------------------------------------------------------------------------- D-Bus plumbing


def session():
    """A session bus, or None when there is no bus to talk to."""
    if dbus is None:
        return None
    try:
        if DBusGMainLoop is not None:
            DBusGMainLoop(set_as_default=True)
        return dbus.SessionBus()
    except Exception:  # noqa: BLE001 - no session bus, headless, bad env
        return None


def _v(value):
    """A dbus.Variant's payload (newer dbus-python hands back plain values)."""
    variant = getattr(dbus, "Variant", None)
    if variant is not None and isinstance(value, variant):
        return value.value
    return value


def _out(reply):
    """dbus-python wraps a lone out arg in a 1-tuple; hand back its payload."""
    if (
        isinstance(reply, (tuple, list))
        and len(reply) == 1
        and isinstance(reply[0], (tuple, list, dict))
    ):
        return reply[0]
    return reply


def pid_of(bus, name):
    try:
        obj = bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus")
        iface = dbus.Interface(obj, "org.freedesktop.DBus")
        try:
            return int(iface.GetConnectionUnixProcessID(name, timeout=T))
        except Exception:  # noqa: BLE001 - a well-known name: resolve its owner first
            return int(
                iface.GetConnectionUnixProcessID(
                    iface.GetNameOwner(name, timeout=T), timeout=T
                )
            )
    except Exception:  # noqa: BLE001
        return None


def introspect(bus, name, path) -> str:
    try:
        obj = bus.get_object(name, path, introspect=False)
        return str(
            dbus.Interface(obj, "org.freedesktop.DBus.Introspectable").Introspect(
                timeout=T
            )
            or ""
        )
    except Exception:  # noqa: BLE001
        return ""


def children_of(xml: str) -> list:
    return re.findall(r'<node\b[^>]*\bname\s*=\s*["\']([^"\']+)["\']', xml or "")


def fmt_shortcut(value) -> str:
    """A D-Bus menu shortcut (list of modifiers + key, or an accel string) -> Ctrl+S."""
    try:
        if isinstance(value, (list, tuple)) and value:
            first = value[0]
            mods = [str(first)] if isinstance(first, str) else list(first)
            accel = "".join("<%s>" % str(m).strip("<>").lower() for m in mods) + str(
                value[-1]
            )
        else:
            accel = str(value or "")
    except Exception:  # noqa: BLE001
        accel = ""
    for a, b in (
        ("<ctrl>", "Ctrl+"),
        ("<Control>", "Ctrl+"),
        ("<Ctrl>", "Ctrl+"),
        ("<primary>", "Ctrl+"),
        ("<Primary>", "Ctrl+"),
        ("<shift>", "Shift+"),
        ("<Shift>", "Shift+"),
        ("<alt>", "Alt+"),
        ("<Alt>", "Alt+"),
        ("<super>", "Super+"),
        ("<Super>", "Super+"),
    ):
        accel = accel.replace(a, b)
    head, _, key = accel.rpartition("+")
    return (head + "+" if head else "") + (key.upper() if len(key) == 1 else key)


# --------------------------------------------------------------------------- com.canonical.dbusmenu


def find_dbusmenu(bus, pid: int):
    """(sender, path) of this pid's menu, via the AppMenu Registrar, else None."""
    try:
        obj = bus.get_object(REG_NAME, REG_PATH)
        menus = _out(dbus.Interface(obj, REG_NAME).GetMenus(timeout=T))
        for _window_id, (sender, path) in menus.items():
            if pid_of(bus, sender) == pid:
                return str(sender), str(path)
    except Exception:  # noqa: BLE001
        pass
    return None


def _layout_children(reply):
    """Children array out of GetLayout: servers wrap it in three different ways."""
    if not isinstance(reply, (tuple, list)):
        return []
    if (
        len(reply) == 1
        and isinstance(reply[0], (tuple, list))
        and len(reply[0]) >= 3
        and isinstance(reply[0][1], dict)
    ):
        return _layout_children(reply[0])  # ((id, props, children),)
    if (
        len(reply) >= 3
        and isinstance(reply[1], dict)
        and isinstance(reply[2], (tuple, list))
    ):
        return list(reply[2])  # (id, props, children)
    if (
        len(reply) >= 2
        and isinstance(reply[1], (tuple, list))
        and (not reply[1] or isinstance(reply[1][0], (tuple, list)))
    ):
        return list(reply[1])  # (something, children)
    if (
        reply
        and isinstance(reply[0], (tuple, list))
        and len(reply[0]) >= 3
        and isinstance(reply[0][1], dict)
    ):
        return list(reply)  # already the children array
    return []


def _dbus_nodes(iface, items, depth: int) -> list:
    out = []
    for item in items or []:
        try:
            item_id, props, kids = item
        except Exception:  # noqa: BLE001
            continue
        try:
            label = str(props.get("label") or "").replace("_", "")
        except Exception:  # noqa: BLE001
            label = ""
        if label in ("Root", "DBusMenuRoot"):
            label = ""
        if props.get("visible", True) is False:
            continue
        try:
            checked = int(props.get("toggle-state", 0)) != 0
        except Exception:  # noqa: BLE001
            checked = bool(props.get("toggle-state"))
        node = {
            "label": label,
            "key": label,
            "id": item_id,
            "enabled": bool(props.get("enabled", True)),
            "visible": True,
            "separator": str(props.get("type") or "") == "separator",
            "toggle_type": str(props.get("toggle-type") or ""),
            "checked": checked,
            "accel": fmt_shortcut(props.get("shortcut")),
            "children": [],
        }
        if node["separator"]:
            out.append(node)
            continue
        if props.get("children-display") and depth < MAX_MENU_DEPTH:
            # GTK only fills a submenu once it is opened; ask it, then close it again.
            try:
                iface.AboutToShow(int(item_id), timeout=T)
                iface.Event(int(item_id), "opened", 0, 0, timeout=T)
            except Exception:  # noqa: BLE001
                pass
            try:
                node["children"] = _dbus_nodes(
                    iface,
                    _layout_children(
                        iface.GetLayout(
                            int(item_id), -1, dbus.Array(signature="s"), timeout=T
                        )
                    ),
                    depth + 1,
                )
            except Exception:  # noqa: BLE001
                node["children"] = _dbus_nodes(iface, kids, depth + 1)
            try:
                iface.Event(int(item_id), "closed", 0, 0, timeout=T)
            except Exception:  # noqa: BLE001
                pass
        elif kids and depth < MAX_MENU_DEPTH:
            node["children"] = _dbus_nodes(iface, kids, depth + 1)
        out.append(node)
    return out


def read_dbusmenu(bus, sender, path) -> list:
    try:
        obj = bus.get_object(sender, path)
        iface = dbus.Interface(obj, "com.canonical.dbusmenu")
        reply = iface.GetLayout(0, -1, dbus.Array(signature="s"), timeout=T)
        return _dbus_nodes(iface, _layout_children(reply), 0)
    except Exception:  # noqa: BLE001
        return []


# --------------------------------------------------------------------------- org.gtk.Menus / org.gtk.Actions


def find_gtk(bus, pid: int, app_id: str = ""):
    """The object paths a GtkApplication exports for this pid, else None."""
    try:
        obj = bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus")
        names_iface = dbus.Interface(obj, "org.freedesktop.DBus")
        names = [str(n) for n in names_iface.ListNames(timeout=T)]
    except Exception:  # noqa: BLE001
        return None

    candidates = [app_id] if app_id and "." in app_id else []
    no_owner = set()  # cache NameHasOwner negatives
    for name in names:
        if name in candidates or name in no_owner:
            continue
        try:
            if not bool(names_iface.NameHasOwner(name, timeout=T)):
                no_owner.add(name)
                continue
        except Exception:  # noqa: BLE001
            no_owner.add(name)
            continue
        if pid_of(bus, name) == pid:
            candidates.append(name)

    for name in candidates:
        try:
            if name in no_owner or not bool(names_iface.NameHasOwner(name, timeout=T)):
                continue
            app_path = "/" + name.replace(".", "/")
            if "org.gtk.Actions" not in introspect(bus, name, app_path):
                continue

            win_path = ""
            for child in children_of(introspect(bus, name, app_path + "/window")):
                p = app_path + "/window/" + child
                if child.isdigit() and introspect(bus, name, p):
                    win_path = p
                    break

            base = app_path + "/menus"
            menubar_path = appmenu_path = ""
            for child in children_of(introspect(bus, name, base)):
                p = base + "/" + child
                if "org.gtk.Menus" not in introspect(bus, name, p):
                    continue
                if p.endswith("/menubar"):
                    menubar_path = p
                elif p.endswith("/appmenu"):
                    appmenu_path = p
            for p in (base + "/menubar", app_path + "/menubar"):
                if not menubar_path and "org.gtk.Menus" in introspect(bus, name, p):
                    menubar_path = p
            for p in (base + "/appmenu", app_path + "/appmenu"):
                if not appmenu_path and "org.gtk.Menus" in introspect(bus, name, p):
                    appmenu_path = p
            if menubar_path or appmenu_path:
                return dict(
                    bus_name=name,
                    app_path=app_path,
                    win_path=win_path,
                    menubar_path=menubar_path,
                    appmenu_path=appmenu_path,
                )
        except Exception:  # noqa: BLE001 - one bad app must not kill the CLI
            continue
    return None


def _action_map(bus, info) -> dict:
    """'app.save' -> (enabled, state, object path exporting it)."""
    actions = {}
    for path, prefix in (
        (info.get("app_path"), "app."),
        (info.get("win_path"), "win."),
        (info.get("menubar_path"), "unity."),
    ):
        if not path:
            continue
        try:
            obj = bus.get_object(info["bus_name"], path, introspect=False)
            described = _out(
                dbus.Interface(obj, "org.gtk.Actions").DescribeAll(timeout=T)
            )
            for name, desc in described.items():
                try:
                    enabled = bool(_v(desc[0]))
                    state = _v(desc[2][0]) if len(desc) > 2 and desc[2] else None
                except Exception:  # noqa: BLE001
                    enabled, state = True, None
                actions[prefix + str(name)] = (enabled, state, path)
        except Exception:  # noqa: BLE001
            continue
    return actions


def _gtk_key(link):
    try:
        return (int(link[0]), int(link[1]))
    except Exception:  # noqa: BLE001
        return None


def _gtk_nodes(key, content, actions, seen, depth: int = 0) -> list:
    if key in seen or depth > MAX_MENU_DEPTH:
        return []
    seen = set(seen) | {key}
    out = []
    for item in content.get(key) or []:
        attrs, links = {}, {}
        for name, value in item.items():
            (links if name.startswith(":") else attrs)[name.lstrip(":")] = _v(value)
        label = str(attrs.get("label") or "").replace("_", "")
        action = str(attrs.get("action") or "")
        raw_target = attrs.get("target")
        target = _v(raw_target) if raw_target is not None else None
        accel = attrs.get("accel", attrs.get("shortcut", ""))
        enabled, checked, toggle_type, action_path = True, False, "", ""
        if action:
            enabled, state, action_path = actions.get(action, (True, None, ""))
            if target is not None:
                toggle_type = "radio"
                try:
                    checked = state == target
                except Exception:  # noqa: BLE001
                    checked = False
            elif isinstance(state, bool):
                toggle_type, checked = "check", state
        node = {
            "label": label,
            "key": label,
            "action": action,
            "target": raw_target,
            "action_path": action_path,
            "enabled": enabled,
            "checked": checked,
            "toggle_type": toggle_type,
            "accel": fmt_shortcut(accel) if accel else "",
            "children": [],
        }
        submenu = _gtk_key(links.get("submenu")) if "submenu" in links else None
        section = _gtk_key(links.get("section")) if "section" in links else None
        if section and not label and not action:
            # a section link is a splice point: its items are siblings, not a child
            out.extend(_gtk_nodes(section, content, actions, seen, depth + 1))
            continue
        if submenu:
            node["children"] = _gtk_nodes(submenu, content, actions, seen, depth + 1)
        elif section:
            node["children"] = _gtk_nodes(section, content, actions, seen, depth + 1)
        out.append(node)
    return out


def read_gtk(bus, info) -> list:
    actions = _action_map(bus, info)
    nodes = []
    for path in (info.get("menubar_path"), info.get("appmenu_path")):
        if not path:
            continue
        try:
            iface = dbus.Interface(
                bus.get_object(info["bus_name"], path, introspect=False),
                "org.gtk.Menus",
            )
            content, asked, queue = {}, set(), [0]
            while queue and len(asked) < 32:
                group = queue.pop(0)
                if group in asked:
                    continue
                asked.add(group)
                try:
                    records = _out(
                        iface.Start(dbus.Array([group], signature="u"), timeout=T)
                    )
                except Exception:  # noqa: BLE001
                    continue
                for record in records or []:
                    try:
                        g, m, items = record
                        g, m = int(g), int(m)
                    except Exception:  # noqa: BLE001
                        continue
                    content[(g, m)] = items
                    for item in items:
                        for name, value in item.items():
                            if not name.startswith(":"):
                                continue
                            linked = _gtk_key(_v(value))
                            if (
                                linked
                                and linked[0] not in asked
                                and linked[0] not in queue
                            ):
                                queue.append(linked[0])
            nodes.extend(_gtk_nodes((0, 0), content, actions, set()))
            try:
                iface.End(
                    dbus.Array(list(asked), signature="u"), timeout=T, ignore_reply=True
                )
            except Exception:  # noqa: BLE001
                pass
        except Exception:  # noqa: BLE001 - one bad app must not kill the CLI
            continue
    return nodes


# --------------------------------------------------------------------------- shared output/activation


def to_menus(nodes):
    """Tree -> the JSON the window menu expects, plus path -> node for activation."""
    index = {}

    def walk(items, prefix, parent_key, depth):
        out = []
        for i, node in enumerate(items or []):
            p = f"{prefix}/{i}" if prefix else str(i)
            if node.get("separator"):
                out.append({"separator": True, "path": p})
                continue
            label = str(node.get("label") or "").replace("_", "")
            kids = (
                walk(node.get("children") or [], p, label, depth + 1)
                if depth < MAX_MENU_DEPTH
                else []
            )
            if not label and not kids:
                continue
            key = parent_key + LABEL_SEP + label if parent_key else label
            out.append(
                {
                    "label": label,
                    "path": p,
                    "enabled": bool(node.get("enabled", True)),
                    "checked": bool(node.get("checked")),
                    "shortcut": node.get("accel") or "",
                    "key": key,
                    "items": kids,
                }
            )
            index[p] = node
        return out

    return walk(nodes, "", "", 0), index


def read_menu(pid: int, title: str = "", app_id: str = "") -> dict:
    """D-Bus menus first; the accessibility tree is the fallback."""
    bus = session()
    if bus is not None:
        found = find_dbusmenu(bus, pid)
        if found:
            try:
                menus, _ = to_menus(read_dbusmenu(bus, *found))
                if menus:
                    return {"menus": menus, "source": "dbusmenu"}
            except Exception:  # noqa: BLE001
                pass
        info = find_gtk(bus, pid, app_id)
        if info:
            try:
                menus, _ = to_menus(read_gtk(bus, info))
                if menus:
                    return {"menus": menus, "source": "gtk"}
            except Exception:  # noqa: BLE001
                pass
    if Atspi is None:
        return {"menus": [], "why": "AT-SPI (at-spi2-core) is not installed"}
    return menu(pid, title)


def do_activate(pid: int, path: str, title: str = "", app_id: str = "") -> dict:
    """Resolve PATH against the app's current menus, then press it."""
    bus = session()
    if bus is not None:
        found = find_dbusmenu(bus, pid)
        if found:
            try:
                _, index = to_menus(read_dbusmenu(bus, *found))
                node = index.get(path)
                if node and "id" in node:
                    iface = dbus.Interface(
                        bus.get_object(found[0], found[1]), "com.canonical.dbusmenu"
                    )
                    iface.Event(int(node["id"]), "clicked", 0, 0, timeout=T)
                    return {"done": True, "label": node.get("label", "")}
            except Exception:  # noqa: BLE001
                pass
        info = find_gtk(bus, pid, app_id)
        if info:
            try:
                _, index = to_menus(read_gtk(bus, info))
                node = index.get(path)
                if node and node.get("action"):
                    target = node.get("target")
                    params = dbus.Array(
                        [] if target is None else [target], signature="v"
                    )
                    owner = node.get("action_path") or info["app_path"]
                    iface = dbus.Interface(
                        bus.get_object(info["bus_name"], owner, introspect=False),
                        "org.gtk.Actions",
                    )
                    iface.Activate(
                        node["action"],
                        params,
                        dbus.Dictionary({}, signature="sv"),
                        timeout=T,
                    )
                    return {"done": True, "label": node.get("label", "")}
            except Exception:  # noqa: BLE001
                pass
    if Atspi is None:
        return {"error": "AT-SPI (at-spi2-core) is not installed"}
    return activate(pid, path, title)


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "menu":
        print(
            json.dumps(
                read_menu(
                    int(argv[2]),
                    argv[3] if len(argv) > 3 else "",
                    argv[4] if len(argv) > 4 else "",
                )
            )
        )
        return 0
    if len(argv) >= 4 and argv[1] == "activate":
        print(
            json.dumps(
                do_activate(
                    int(argv[2]),
                    argv[3],
                    argv[4] if len(argv) > 4 else "",
                    argv[5] if len(argv) > 5 else "",
                )
            )
        )
        return 0
    print(
        "usage: appmenu.py menu PID [TITLE] [APP_ID] | activate PID PATH [TITLE] [APP_ID]",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
