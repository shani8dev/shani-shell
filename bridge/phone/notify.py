"""Who Phone's notifications say they are from.

Every notification the service or the app posts names Phone itself - its
app name and its desktop id - so the desktop draws Phone's icon beside a
call or a text, not another app's. One place, so the next notification cannot
borrow somebody else's face again (they all said "Shani Chronoa" once, from
the days this code lived there).
"""
from __future__ import annotations

APP_NAME = "Phone"
#: The app's desktop file (data/applications/dev.shani.Shell.Phone.App.desktop).
APP_ENTRY = "dev.shani.Shell.Phone.App"


def hints(category: str, **extra) -> dict:
    """The `a{sv}` hints for a Notify call: the category, the desktop id, and `extra`
    (already GLib.Variants)."""
    from gi.repository import GLib
    out = {"category": GLib.Variant("s", category), "desktop-entry": GLib.Variant("s", APP_ENTRY)}
    out.update(extra)
    return out


def send_argv(title: str, body: str, icon: str = "") -> "list[str]":
    """`notify-send`, as Phone."""
    argv = ["notify-send", f"--app-name={APP_NAME}", f"--hint=string:desktop-entry:{APP_ENTRY}"]
    if icon:
        argv.append(f"--icon={icon}")
    return argv + [title, body]
