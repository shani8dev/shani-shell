"""A stand-in udisks2 on the session bus: a USB stick (/dev/sdb, one mounted
partition) and the computer's own disk (/dev/nvme0n1). Block.OpenForRestore hands
over a file ($FAKE_UDISKS_DIR/sdb.img) as the drive; every other call is written
to $FAKE_UDISKS_DIR/calls, one JSON line each."""
import json
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

D = os.environ["FAKE_UDISKS_DIR"]
U = "org.freedesktop.UDisks2"
P = "/org/freedesktop/UDisks2"
XML = """<node>
<interface name='org.freedesktop.DBus.ObjectManager'><method name='GetManagedObjects'><arg type='a{oa{sa{sv}}}' direction='out'/></method></interface>
<interface name='org.freedesktop.UDisks2.Block'>
 <method name='OpenForRestore'><arg type='a{sv}' direction='in'/><arg type='h' direction='out'/></method>
 <method name='OpenForBackup'><arg type='a{sv}' direction='in'/><arg type='h' direction='out'/></method>
 <method name='Format'><arg type='s' direction='in'/><arg type='a{sv}' direction='in'/></method></interface>
<interface name='org.freedesktop.UDisks2.PartitionTable'>
 <method name='CreatePartitionAndFormat'><arg type='t' direction='in'/><arg type='t' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='a{sv}' direction='in'/><arg type='s' direction='in'/><arg type='a{sv}' direction='in'/><arg type='o' direction='out'/></method></interface>
<interface name='org.freedesktop.UDisks2.Filesystem'><method name='Unmount'><arg type='a{sv}' direction='in'/></method>
 <method name='Mount'><arg type='a{sv}' direction='in'/><arg type='s' direction='out'/></method></interface>
<interface name='org.freedesktop.UDisks2.Manager'><method name='LoopSetup'><arg type='h' direction='in'/><arg type='a{sv}' direction='in'/><arg type='o' direction='out'/></method></interface>
<interface name='org.freedesktop.UDisks2.Encrypted'><method name='ChangePassphrase'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='a{sv}' direction='in'/></method></interface>
<interface name='org.freedesktop.UDisks2.Loop'><method name='SetAutoclear'><arg type='b' direction='in'/><arg type='a{sv}' direction='in'/></method></interface>
</node>"""
NODE = Gio.DBusNodeInfo.new_for_xml(XML)


def ay(s):
    return GLib.Variant("ay", s.encode() + b"\0")


def tree():
    s, b = GLib.Variant("s", ""), GLib.Variant
    return {
        P + "/drives/SanDisk": {U + ".Drive": {"Vendor": b("s", "SanDisk"), "Model": b("s", "Cruzer Blade"), "Removable": b("b", True),
                                                "MediaRemovable": b("b", False), "MediaAvailable": b("b", True), "ConnectionBus": b("s", "usb"), "Size": b("t", 1 << 30)}},
        P + "/drives/Samsung": {U + ".Drive": {"Vendor": b("s", "Samsung"), "Model": b("s", "SSD 980"), "Removable": b("b", False),
                                                "MediaRemovable": b("b", False), "MediaAvailable": b("b", True), "ConnectionBus": s, "Size": b("t", 1 << 40)}},
        P + "/block_devices/sdb": {U + ".Block": {"Device": ay("/dev/sdb"), "PreferredDevice": ay("/dev/sdb"), "Drive": b("o", P + "/drives/SanDisk"), "IdLabel": s, "IdType": s},
                                   U + ".PartitionTable": {"Type": b("s", "dos")}},
        P + "/block_devices/sdb1": {U + ".Block": {"Device": ay("/dev/sdb1"), "PreferredDevice": ay("/dev/sdb1"), "Drive": b("o", P + "/drives/SanDisk"),
                                                    "IdLabel": b("s", "STICK"), "IdType": b("s", "vfat")},
                                    U + ".Partition": {"Number": b("u", 1)},
                                    **({U + ".Encrypted": {"HintEncryptionType": b("s", "luks2")}} if os.environ.get("FAKE_LUKS") else {}),
                                    U + ".Filesystem": {"MountPoints": GLib.Variant("aay", [b"/run/media/me/STICK\0"])}},
        **({P + "/block_devices/loop0": {U + ".Block": {"Device": ay("/dev/loop0"), "PreferredDevice": ay("/dev/loop0"), "Drive": b("o", "/"),
                                                       "IdLabel": b("s", "ARCH_202611"), "IdType": b("s", "iso9660")},
                                          U + ".Loop": {"BackingFile": ay(LOOPED[0])},
                                          U + ".Filesystem": {"MountPoints": GLib.Variant("aay", [])}}} if LOOPED else {}),
        P + "/block_devices/nvme0n1": {U + ".Block": {"Device": ay("/dev/nvme0n1"), "PreferredDevice": ay("/dev/nvme0n1"), "Drive": b("o", P + "/drives/Samsung"), "IdLabel": s, "IdType": s}},
    }


LOOPED = []          # the image a LoopSetup was handed (its path, read from the fd)


def log(obj, method, args):
    with open(os.path.join(D, "calls"), "a") as f:
        f.write(json.dumps([obj.rsplit("/", 1)[1], method, args]) + "\n")


def call(conn, sender, obj, iface, method, params, inv):
    args = params.unpack()
    if method == "GetManagedObjects":
        inv.return_value(GLib.Variant("(a{oa{sa{sv}}})", (tree(),)))
        return
    if method == "OpenForRestore":
        log(obj, method, [])
        fd = os.open(os.path.join(D, obj.rsplit("/", 1)[1] + ".img"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
        fds = Gio.UnixFDList.new()
        fds.append(fd)
        os.close(fd)
        inv.return_value_with_unix_fd_list(GLib.Variant("(h)", (0,)), fds)
        return
    if method == "LoopSetup":
        fd = inv.get_message().get_unix_fd_list().get(args[0])
        LOOPED[:] = [os.readlink("/proc/self/fd/%d" % fd)]
        ro = params.unpack()[1].get("read-only")
        os.close(fd)
        log(obj, method, [os.path.basename(LOOPED[0]), {"read-only": ro}])
        inv.return_value(GLib.Variant("(o)", (P + "/block_devices/loop0",)))
        return
    if method == "OpenForBackup":
        log(obj, method, [])
        src = os.path.join(D, obj.rsplit("/", 1)[1] + ".disk")
        fd = os.open(src, os.O_RDONLY)
        fds = Gio.UnixFDList.new()
        fds.append(fd)
        os.close(fd)
        inv.return_value_with_unix_fd_list(GLib.Variant("(h)", (0,)), fds)
        return
    if method == "ChangePassphrase":
        if args[0] != "old-pw":
            inv.return_dbus_error("org.freedesktop.UDisks2.Error.Failed", "Error changing passphrase: Failed to activate device: Operation not permitted")
            return
        log(obj, method, [])
        inv.return_value(None)
        return
    if method == "Mount":
        log(obj, method, [])
        inv.return_value(GLib.Variant("(s)", ("/run/media/me/ARCH_202611",)))
        return
    log(obj, method, [a for a in args if not isinstance(a, dict)] + [{k: v for k, v in a.items() if k != "auth.no_user_interaction"} for a in args if isinstance(a, dict)])
    inv.return_value(GLib.Variant("(o)", (P + "/block_devices/sdb1",)) if method == "CreatePartitionAndFormat" else None)


def acquired(conn, name):
    for path in list(tree()) + [P, P + "/Manager", P + "/block_devices/loop0"]:
        for i in NODE.interfaces:
            conn.register_object(path, i, call, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, U, Gio.BusNameOwnerFlags.NONE, acquired, lambda *a: open(os.path.join(D, "ready"), "w").close(), lambda *a: sys.exit(1))
GLib.MainLoop().run()
