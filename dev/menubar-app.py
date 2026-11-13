#!/usr/bin/env python3
"""A GTK 3 app with a real menu bar, for the window menu's app menus
(bridge/appmenu.py, dev/shell-parts/app-menu.sh): File > New / Save (Ctrl+S,
writes /tmp/menubar-saved) / Recent > a.txt, b.txt / Quit, and Edit > Wrap lines
(a check item, on). Every item it runs is written to /tmp/menubar-saved."""
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

OUT = "/tmp/menubar-saved"


def did(what):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(what + "\n")


win = Gtk.Window(title="Menu bar test")
win.set_default_size(520, 320)
accel = Gtk.AccelGroup()
win.add_accel_group(accel)
bar = Gtk.MenuBar()


def menu(label, items):
    top = Gtk.MenuItem.new_with_mnemonic(label)
    sub = Gtk.Menu()
    for it in items:
        sub.append(it)
    top.set_submenu(sub)
    bar.append(top)


def item(label, key=None):
    it = Gtk.MenuItem.new_with_mnemonic(label)
    it.connect("activate", lambda _w: did(label.replace("_", "")))
    if key:
        k, mods = Gtk.accelerator_parse(key)
        it.add_accelerator("activate", accel, k, mods, Gtk.AccelFlags.VISIBLE)
    return it


recent = Gtk.MenuItem.new_with_mnemonic("_Recent")
rsub = Gtk.Menu()
for name in ("a.txt", "b.txt"):
    rsub.append(item(name))
recent.set_submenu(rsub)
wrap = Gtk.CheckMenuItem.new_with_mnemonic("_Wrap lines")
wrap.set_active(True)
menu("_File", [item("_New", "<Control>n"), item("_Save", "<Control>s"), recent, Gtk.SeparatorMenuItem(), item("_Quit")])
menu("_Edit", [wrap, item("_Copy", "<Control>c")])

box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
box.pack_start(bar, False, False, 0)
box.pack_start(Gtk.Label(label="A window with a menu bar"), True, True, 0)
win.add(box)
win.connect("destroy", Gtk.main_quit)
win.show_all()
Gtk.main()
