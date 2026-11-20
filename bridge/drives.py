#!/usr/bin/env python3
"""drives — removable drives: list them, format one, write a disk image to one.
What Impression (write an image) and GNOME Disks' "Format" did, through udisks2
over D-Bus - the same service, so the same polkit question ("Authentication is
required to modify ..."), answered by the shell's own polkit agent.

    drives.py list                      [{"block", "name", "size", "parts": [...]}]
    drives.py format <block> <fs> <label> [--encrypt]
                                        fs: exfat vfat ntfs ext4 btrfs f2fs xfs udf;
                                        --encrypt: LUKS2 with the password read
                                        from stdin (never on the command line)
    drives.py mount-image <image>       a disk image (.iso, .img) opened read-only as
                                        a drive and its file systems mounted:
                                        {"paths": [...], "device"}; ejecting it
                                        (gio, as any drive) lets it go again
    drives.py backup <block> <out.img> the whole drive copied into an image file
                                        (GNOME Disks' "Create Disk Image"); prints
                                        {"done", "total"} lines, then {"ok"}
    drives.py passphrase <block>        {"old", "new"} on stdin: a locked (LUKS)
                                        drive's password changed
    drives.py write <image> <block>     the image's bytes onto the whole drive;
                                        prints {"done", "total"} lines, then {"ok"}
                                        (.xz, .gz, .bz2 and .zst images unpacked
                                        on the way, as Impression does)

Only drives udisks calls removable (a USB stick, an SD card) are listed or
accepted: the computer's own disk is never offered. SIGTERM stops a write.
SHANI_UDISKS_BUS=session (tests): udisks looked for on the session bus.
"""
from __future__ import annotations

import json
import os
import signal
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "org.freedesktop.UDisks2"
ROOT = "/org/freedesktop/UDisks2"
# what udisks formats with (mkfs from shani-storage), and the MBR type each wants
FS = {"exfat": "0x07", "vfat": "0x0c", "ntfs": "0x07", "ext4": "0x83", "btrfs": "0x83",
      "f2fs": "0x83", "xfs": "0x83", "udf": "0x07"}


def bus() -> Gio.DBusConnection:
    kind = Gio.BusType.SESSION if os.environ.get("SHANI_UDISKS_BUS") == "session" else Gio.BusType.SYSTEM
    return Gio.bus_get_sync(kind, None)


def _bytes(v) -> str:
    return bytes(v).rstrip(b"\0").decode(errors="replace") if v else ""


def objects(c: Gio.DBusConnection) -> dict:
    r = c.call_sync(NAME, ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
                    None, GLib.VariantType("(a{oa{sa{sv}}})"), Gio.DBusCallFlags.NONE, -1, None)
    return r.unpack()[0]


def drives(objs: dict) -> list[dict]:
    """The removable drives, each with its whole-disk block device and partitions."""
    out = []
    for path, ifs in sorted(objs.items()):
        d = ifs.get("org.freedesktop.UDisks2.Drive")
        if not d or not (d.get("Removable") or d.get("MediaRemovable") or d.get("ConnectionBus") == "usb"):
            continue
        if not d.get("MediaAvailable", True) or d.get("Size", 0) == 0:
            continue
        whole, parts = None, []
        for bp, bifs in objs.items():
            b = bifs.get("org.freedesktop.UDisks2.Block")
            if not b or b.get("Drive") != path:
                continue
            dev = _bytes(b.get("PreferredDevice") or b.get("Device"))
            if "org.freedesktop.UDisks2.Partition" in bifs:
                fs = bifs.get("org.freedesktop.UDisks2.Filesystem")
                parts.append({"device": dev, "label": b.get("IdLabel", ""), "fs": b.get("IdType", ""),
                              "mounted": [_bytes(m) for m in (fs or {}).get("MountPoints", [])]})
            else:
                whole = {"object": bp, "device": dev}
        if not whole:
            continue
        name = " ".join(x for x in (d.get("Vendor", "").strip(), d.get("Model", "").strip()) if x) or whole["device"]
        out.append({"block": whole["object"], "device": whole["device"], "name": name,
                    "size": d.get("Size", 0), "parts": sorted(parts, key=lambda p: p["device"])})
    return out


def _removable(c, block: str) -> dict:
    for d in drives(objects(c)):
        if d["block"] == block or d["device"] == block:
            return d
    raise LookupError("not a removable drive: %s" % block)


def _opts(**kw) -> dict:
    v = {"auth.no_user_interaction": GLib.Variant("b", False)}
    for k, x in kw.items():
        v[k.replace("encrypt_", "encrypt.").replace("_", "-")] = GLib.Variant("s", x) if isinstance(x, str) else GLib.Variant("b", x)
    return v


def _unmount_all(c, d: dict, objs: dict) -> None:
    for bp, bifs in objs.items():
        b = bifs.get("org.freedesktop.UDisks2.Block")
        fs = bifs.get("org.freedesktop.UDisks2.Filesystem")
        if b and fs and fs.get("MountPoints") and _bytes(b.get("PreferredDevice") or b.get("Device")) in [p["device"] for p in d["parts"]]:
            c.call_sync(NAME, bp, "org.freedesktop.UDisks2.Filesystem", "Unmount",
                        GLib.Variant("(a{sv})", (_opts(),)), None, Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, -1, None)


def format_drive(block: str, fs: str, label: str, passphrase: str = "") -> dict:
    if fs not in FS:
        return {"error": "unknown file system: %s" % fs}
    c = bus()
    objs = objects(c)
    d = _removable(c, block)
    _unmount_all(c, d, objs)
    flags = Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION
    # a fresh MBR table (what every camera, TV and car stereo reads), then one
    # partition over all of it, formatted
    c.call_sync(NAME, d["block"], "org.freedesktop.UDisks2.Block", "Format",
                GLib.Variant("(sa{sv})", ("dos", _opts())), None, flags, 600000, None)
    fsopts = {"label": label[:11] if fs == "vfat" else label} if label else {}
    if passphrase:
        fsopts.update({"encrypt_passphrase": passphrase, "encrypt_type": "luks2"})
    r = c.call_sync(NAME, d["block"], "org.freedesktop.UDisks2.PartitionTable", "CreatePartitionAndFormat",
                    GLib.Variant("(ttssa{sv}sa{sv})", (1 << 20, 0, FS[fs], "", _opts(), fs, _opts(**fsopts))),
                    GLib.VariantType("(o)"), flags, 600000, None)
    return {"ok": True, "partition": r.unpack()[0]}


def _reader(path: str):
    """(the image's bytes as a stream, the file underneath - whose position is how far
    along the image is, the only size known up front for a packed one)"""
    raw = open(path, "rb")
    low = path.lower()
    if low.endswith(".xz"):
        import lzma
        return lzma.open(raw, "rb"), raw
    if low.endswith(".gz"):
        import gzip
        return gzip.open(raw, "rb"), raw
    if low.endswith(".bz2"):
        import bz2
        return bz2.open(raw, "rb"), raw
    if low.endswith(".zst"):
        import subprocess
        return subprocess.Popen(["zstd", "-dc"], stdin=raw, stdout=subprocess.PIPE).stdout, raw
    return raw, raw


def write_image(image: str, block: str) -> int:
    total = os.path.getsize(image)
    c = bus()
    objs = objects(c)
    d = _removable(c, block)
    raw = not image.lower().endswith((".xz", ".gz", ".bz2", ".zst"))
    if raw and total > d["size"]:
        print(json.dumps({"error": "the image (%d bytes) is bigger than the drive (%d)" % (total, d["size"])}))
        return 1
    _unmount_all(c, d, objs)
    r, fds = c.call_with_unix_fd_list_sync(NAME, d["block"], "org.freedesktop.UDisks2.Block", "OpenForRestore",
                                           GLib.Variant("(a{sv})", (_opts(),)), GLib.VariantType("(h)"),
                                           Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, -1, None, None)
    out = os.fdopen(fds.get(r.unpack()[0]), "wb", buffering=0)
    stop = []
    signal.signal(signal.SIGTERM, lambda *_: stop.append(1))
    done, last = 0, -1
    src, under = _reader(image)
    with src, under, out:
        while not stop:
            chunk = src.read(4 << 20)
            if not chunk:
                break
            if done + len(chunk) > d["size"]:
                print(json.dumps({"error": "the image is bigger than the drive"}), flush=True)
                return 1
            out.write(chunk)
            done += len(chunk)
            at = under.tell()
            pct = int(min(at, total) * 100 / total) if total else 100
            if pct != last:
                last = pct
                print(json.dumps({"done": min(at, total), "total": total}), flush=True)
        os.fsync(out.fileno())
    if stop:
        print(json.dumps({"error": "stopped; the drive holds part of the image, format it to use it again"}), flush=True)
        return 1
    print(json.dumps({"ok": True, "written": done}), flush=True)
    return 0


def mount_image(image: str) -> dict:
    """Disk Image Mounter's job: Manager.LoopSetup read-only with autoclear (the loop
    device goes when its last file system is unmounted), then each file system on it
    - the image itself (an ISO) or its partitions (a disk's image) - mounted."""
    import time
    c = bus()
    flags = Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION
    fd = os.open(image, os.O_RDONLY)
    fds = Gio.UnixFDList.new()
    fds.append(fd)
    os.close(fd)
    r, _ = c.call_with_unix_fd_list_sync(NAME, ROOT + "/Manager", "org.freedesktop.UDisks2.Manager", "LoopSetup",
                                         GLib.Variant("(ha{sv})", (0, _opts(read_only=True))), GLib.VariantType("(o)"),
                                         flags, -1, fds, None)
    loop = r.unpack()[0]
    try:
        c.call_sync(NAME, loop, "org.freedesktop.UDisks2.Loop", "SetAutoclear",
                    GLib.Variant("(ba{sv})", (True, _opts())), None, flags, -1, None)
    except GLib.Error:
        pass
    # the partitions of an image show up a moment after the loop device itself
    paths, device = [], ""
    for _ in range(20):
        objs = objects(c)
        device = _bytes(objs.get(loop, {}).get("org.freedesktop.UDisks2.Block", {}).get("Device"))
        targets = [p for p, ifs in sorted(objs.items()) if "org.freedesktop.UDisks2.Filesystem" in ifs
                   and (p == loop or ifs.get("org.freedesktop.UDisks2.Partition", {}).get("Table") == loop)]
        if targets:
            break
        time.sleep(0.25)
    for p in targets:
        mounted = [_bytes(m) for m in objs[p]["org.freedesktop.UDisks2.Filesystem"].get("MountPoints", [])]
        if mounted:
            paths += mounted
            continue
        try:
            r = c.call_sync(NAME, p, "org.freedesktop.UDisks2.Filesystem", "Mount", GLib.Variant("(a{sv})", (_opts(),)),
                            GLib.VariantType("(s)"), flags, -1, None)
            paths.append(r.unpack()[0])
        except GLib.Error:
            pass                                       # a swap or unknown partition: not a place
    if not paths:
        return {"error": "nothing on this image can be opened", "device": device}
    return {"paths": paths, "device": device}


def backup(block: str, out: str) -> int:
    """GNOME Disks' Create Disk Image: Block.OpenForBackup, read to the end, into a
    new file (never over one). SIGTERM stops it and takes the half-made file back."""
    c = bus()
    d = _removable(c, block)
    if os.path.lexists(out):
        print(json.dumps({"error": "%s is there already" % os.path.basename(out)}), flush=True)
        return 1
    r, fds = c.call_with_unix_fd_list_sync(NAME, d["block"], "org.freedesktop.UDisks2.Block", "OpenForBackup",
                                           GLib.Variant("(a{sv})", (_opts(),)), GLib.VariantType("(h)"),
                                           Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, -1, None, None)
    src = os.fdopen(fds.get(r.unpack()[0]), "rb", buffering=0)
    stop = []
    signal.signal(signal.SIGTERM, lambda *_: stop.append(1))
    total, done, last = d["size"], 0, -1
    with src, open(out, "xb") as dst:
        while not stop:
            chunk = src.read(4 << 20)
            if not chunk:
                break
            dst.write(chunk)
            done += len(chunk)
            pct = int(done * 100 / total) if total else 100
            if pct != last:
                last = pct
                print(json.dumps({"done": done, "total": total}), flush=True)
    if stop:
        os.remove(out)                                   # the half-made image only
        print(json.dumps({"error": "stopped"}), flush=True)
        return 1
    print(json.dumps({"ok": True, "written": done, "path": out}), flush=True)
    return 0


def passphrase(block: str, old: str, new: str) -> dict:
    """A locked removable drive's password changed (Encrypted.ChangePassphrase on
    its LUKS partition, or the drive itself when it is LUKS all through)."""
    if not new:
        return {"error": "no new password given"}
    c = bus()
    objs = objects(c)
    d = _removable(c, block)
    devs = {d["device"]} | {p["device"] for p in d["parts"]}
    for bp, bifs in objs.items():
        b = bifs.get("org.freedesktop.UDisks2.Block")
        if b and "org.freedesktop.UDisks2.Encrypted" in bifs and _bytes(b.get("PreferredDevice") or b.get("Device")) in devs:
            c.call_sync(NAME, bp, "org.freedesktop.UDisks2.Encrypted", "ChangePassphrase",
                        GLib.Variant("(ssa{sv})", (old, new, _opts())), None, Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, -1, None)
            return {"ok": True}
    return {"error": "this drive is not locked with a password"}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    try:
        if cmd == "list" and not args:
            print(json.dumps(drives(objects(bus()))))
            return 0
        if cmd == "format" and len(args) in (3, 4) and args[3:] in ([], ["--encrypt"]):
            pw = sys.stdin.readline().rstrip("\n") if args[3:] else ""
            if args[3:] and not pw:
                print(json.dumps({"error": "no password given"}))
                return 1
            r = format_drive(*args[:3], passphrase=pw)
            print(json.dumps(r))
            return 0 if r.get("ok") else 1
        if cmd == "mount-image" and len(args) == 1:
            r = mount_image(args[0])
            print(json.dumps(r))
            return 0 if "paths" in r else 1
        if cmd == "backup" and len(args) == 2:
            return backup(*args)
        if cmd == "passphrase" and len(args) == 1:
            try:
                a = json.loads(sys.stdin.readline() or "{}")
            except ValueError:
                a = {}
            r = passphrase(args[0], a.get("old", ""), a.get("new", ""))
            print(json.dumps(r))
            return 0 if r.get("ok") else 1
        if cmd == "write" and len(args) == 2:
            return write_image(*args)
    except LookupError as e:
        print(json.dumps({"error": str(e)}), flush=True)
        return 1
    except GLib.Error as e:
        msg = e.message
        if "Failed to activate" in msg or "No key available" in msg or "passphrase" in msg.lower():
            msg = "the old password is not right"
        elif "NotAuthorized" in msg or "dismissed" in msg.lower():
            msg = "not allowed (the administrator's password was not given)"
        print(json.dumps({"error": msg}), flush=True)
        return 1
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
