#!/usr/bin/env python3
"""a11y-tree — what a screen reader sees of the shell: walk the AT-SPI tree of
the Quickshell process and print `role<TAB>name<TAB>state` lines.

    a11y-tree.py [NAME-FILTER]
"""
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

want = sys.argv[1].lower() if len(sys.argv) > 1 else ""


def walk(node, depth=0):
    if node is None or depth > 40:
        return
    try:
        name, role = node.get_name() or "", node.get_role_name()
        states = node.get_state_set()
        checked = "checked" if states.contains(Atspi.StateType.CHECKED) else ""
    except Exception:  # noqa: BLE001 - a vanishing node is not an error
        return
    if name and (not want or want in name.lower()):
        print(f"{role}\t{name}\t{checked}")
    for i in range(node.get_child_count()):
        walk(node.get_child_at_index(i), depth + 1)


desktop = Atspi.get_desktop(0)
for i in range(desktop.get_child_count()):
    app = desktop.get_child_at_index(i)
    if app and (app.get_name() or "").lower() in ("quickshell", "qs"):
        walk(app)
