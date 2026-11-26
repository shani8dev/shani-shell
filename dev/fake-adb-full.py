#!/usr/bin/env python3
"""adb stand-in for the Devices window and the Android tools' live check.

Answers exactly the verbs the phone panels ask, and nothing else — every call
is logged to $SHANI_ADB_LOG so a check can assert what the window did. No call
reaches a real device: the handset, its battery and its screen are data here.

  adb devices [-l]                  one ready Pixel 7 on USB
  adb -s SERIAL shell dumpsys battery
  adb -s SERIAL shell dumpsys diskstats
  adb -s SERIAL shell df -h /sdcard
  adb -s SERIAL exec-out screencap -p      a real, deterministic PNG
  adb -s SERIAL shell pm list packages [-3]
  adb -s SERIAL push SRC DST               copies into $SHANI_ADB_STATE
  adb -s SERIAL pull REMOTE LOCAL          writes a fixed file here
  adb -s SERIAL shell am start ...         logs the link it opened
  adb -s SERIAL shell monkey -p PKG ...    logs the app it opened
  adb -s SERIAL shell getprop KEY          fixed build properties
  adb -s SERIAL shell screenrecord ...     logs the recording
  adb connect HOST:PORT                    adds a Wi-Fi handset
  adb pair HOST:PORT CODE                  Wi-Fi debugging pairing
  adb install [-r] APK                     app install result
  adb -s SERIAL shell ls -lR DIRS          media listing from the phone tree
  adb -s SERIAL shell content query ...    contacts / texts / call log
  adb -s SERIAL shell svc usb ...          USB tethering state

Env:
  SHANI_ADB_LOG          call log (default /tmp/fake-adb-calls)
  SHANI_ADB_STATE        scratch dir for push/pull (default /tmp/fake-adb-state)
  SHANI_FAKE_PHONE_DIR   when set, the phone tree behind /sdcard, contacts.vcf,
                         sms.txt and calls.txt (dev/fake-android-phone.py builds it)

Old verbs keep their answers when SHANI_FAKE_PHONE_DIR is unset, so the Devices
window's live check is untouched.
"""

from __future__ import annotations

import os
import shutil
import struct
import sys
import zlib
from datetime import datetime
from pathlib import Path

SERIAL = "0A1B2C3D"
MODEL = "Pixel_7"
BATTERY = 76
FREE = "50G"


def log(argv: list[str]) -> None:
    # A log that cannot be written must never suppress the answer, least of all
    # the binary screenshot.
    try:
        path = Path(os.environ.get("SHANI_ADB_LOG", "/tmp/fake-adb-calls"))
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(" ".join(argv) + "\n")
    except OSError:
        pass


def state_dir() -> Path:
    return Path(os.environ.get("SHANI_ADB_STATE", "/tmp/fake-adb-state"))


def phone_dir() -> "Path | None":
    raw = os.environ.get("SHANI_FAKE_PHONE_DIR", "").strip()
    return Path(raw) if raw else None


def sdcard_local(remote: str) -> "Path | None":
    base = phone_dir()
    if base and remote.startswith("/sdcard/"):
        return base / "sdcard" / remote[len("/sdcard/") :]
    return None


def stamp(path: Path) -> str:
    return datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d %H:%M")


def ls_recursive(paths: list[str]) -> None:
    """`ls -lR` from the fake phone tree, in the form the bridge parses."""
    base = phone_dir()
    if base is None:
        for path in paths:
            print(path + ":")
        return
    shared = base / "sdcard"
    for remote in paths:
        root = sdcard_local(remote)
        if root is None or not root.is_dir():
            continue
        folders = [root] + [p for p in sorted(root.rglob("*")) if p.is_dir()]
        for folder in folders:
            rel = folder.relative_to(shared)
            header = ("/sdcard/" + str(rel)) if str(rel) != "." else remote
            print(header + ":")
            entries = sorted(folder.iterdir(), key=lambda p: p.name)
            print("total %d" % len(entries))
            for entry in entries:
                mode = "drwxr-xr-x" if entry.is_dir() else "-rw-r--r--"
                size = 4096 if entry.is_dir() else entry.stat().st_size
                print(
                    "%s 1 root sdcard_rw %d %s %s"
                    % (mode, size, stamp(entry), entry.name)
                )
            print()


def content_query(argv: list[str]) -> int:
    """The three content locations android_tools reads, from the fake phone tree."""
    base = phone_dir()
    if base is None:
        sys.stderr.write("Error: no phone data is available\n")
        return 1
    uri = argv[argv.index("--uri") + 1] if "--uri" in argv else ""
    if "contacts" in uri:
        source = base / "contacts.vcf"
        if not source.is_file():
            sys.stderr.write("Error: the phone refused to share contacts\n")
            return 1
        rows, name = [], ""
        for line in source.read_text(errors="replace").splitlines():
            upper = line.upper()
            if upper.startswith("FN:"):
                name = line[3:].strip()
            elif upper.startswith("TEL") and ":" in line:
                rows.append((name, line.split(":", 1)[1].strip()))
                name = ""
        for number, (who, tel) in enumerate(rows):
            print("Row: %d display_name=%s, data1=%s" % (number, who, tel))
        return 0
    if "sms" in uri:
        source = base / "sms.txt"
        if not source.is_file():
            sys.stderr.write("Error: the phone refused to share texts\n")
            return 1
        for number, line in enumerate(source.read_text(errors="replace").splitlines()):
            cells = line.split("|")
            if len(cells) < 3:
                continue
            print(
                "Row: %d address=%s, date=%s, body=%s"
                % (number, cells[0], cells[1], cells[2])
            )
        return 0
    if "call_log" in uri:
        source = base / "calls.txt"
        if not source.is_file():
            sys.stderr.write("Error: the phone refused to share its call log\n")
            return 1
        for number, line in enumerate(source.read_text(errors="replace").splitlines()):
            cells = line.split("|")
            if len(cells) < 3:
                continue
            print(
                "Row: %d name=%s, number=%s, date=%s, type=%s"
                % (
                    number,
                    cells[0],
                    cells[1],
                    cells[2],
                    cells[3] if len(cells) > 3 else "1",
                )
            )
        return 0
    sys.stderr.write("Error: the phone does not keep that record\n")
    return 1


def png(width: int = 16, height: int = 16) -> bytes:
    """A small valid RGB PNG, built with the standard library only."""

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    row = b"\x00" + bytes([32, 96, 160]) * width  # filter byte + pixels
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(row * height, 9))
        + chunk(b"IEND", b"")
    )


def devices(long: bool = False) -> None:
    print("List of devices attached")
    suffix = (
        " usb:1-2 product:panther model:%s device:panther transport_id:1" % MODEL
        if long
        else ""
    )
    print("%s\tdevice%s" % (SERIAL, suffix))
    print()


def battery() -> None:
    print("Current Battery Service state:")
    print("  AC powered: false")
    print("  USB powered: true")
    print("  Wireless powered: false")
    print("  status: 2")
    print("  health: 2")
    print("  level: %d" % BATTERY)
    print("  scale: 100")
    print("  voltage: 3900000")
    print("  temperature: 250")


def diskstats() -> None:
    print("Data partition size: 128871395328")
    print("Available: 53687091200")
    print("Free blocks: 13107200")


def df() -> None:
    print("Filesystem            Size  Used Avail Use% Mounted on")
    print("/dev/block/mmcblk0p1  116G   61G  %s  55%% /sdcard" % FREE)


def packages(user_only: bool) -> None:
    if not user_only:
        print("package:android")
        print("package:com.android.settings")
    for name in ("com.example.notes", "org.shani.testapp"):
        print("package:" + name)


def display() -> None:
    print(
        "DisplayDeviceInfo{id 0, 1080 x 2400, modeId 1, renderFrameRate 120.0, "
        "density 440, HdrCapabilities{mSupportedHdrTypes=[HDR10]}}"
    )


def getprop(key: str) -> None:
    props = {
        "ro.product.manufacturer": "Google",
        "ro.product.model": "Pixel 7",
        "ro.build.version.release": "16",
        "ro.build.version.security_patch": "2026-10-05",
    }
    print(props.get(key, ""))


def main() -> int:
    argv = sys.argv[1:]
    log(argv)
    # adb -s SERIAL ... ; Mirror.qml calls plain `adb devices -l`
    if argv and argv[0] == "-s":
        argv = argv[2:]
    if not argv:
        return 0

    if argv[0] == "devices":
        devices("-l" in argv)
    elif argv[0] == "connect":
        print("connected to %s" % (argv[1] if len(argv) > 1 else ""))
    elif argv[0] == "disconnect":
        print("disconnected %s" % (argv[1] if len(argv) > 1 else ""))
    elif argv[0] == "pair":
        print("Successfully paired to %s" % (argv[1] if len(argv) > 1 else ""))
    elif argv[0] == "install":
        base = phone_dir()
        if base is not None and (base / "refuse-install").exists():
            print("Failure [INSTALL_FAILED_USER_RESTRICTED]")
            return 1
        print("Success")
    elif argv == ["exec-out", "screencap", "-p"]:
        # raw fd 1: no text wrapper or encoding can touch the PNG bytes
        os.write(1, png())
    elif argv[:1] == ["push"] and len(argv) >= 3:
        src, dst = Path(argv[1]), Path(argv[2])
        if not src.is_file():
            sys.stderr.write("%s: no such file\n" % src)
            return 1
        # a subdir keeps the copy away from the source when both are in /tmp
        target = state_dir() / "sdcard" / dst.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, target)
        local = sdcard_local(str(dst))
        if local is not None:
            local.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, local)
        print("%s: 1 file pushed" % src.name)
    elif argv[:1] == ["pull"] and len(argv) >= 3:
        target = Path(argv[2])
        target.parent.mkdir(parents=True, exist_ok=True)
        local = sdcard_local(argv[1])
        if local is not None and local.is_file():
            shutil.copyfile(local, target)
        else:
            target.write_bytes(("from the phone: " + argv[1] + "\n").encode())
        print("%s: 1 file pulled" % argv[1])
    elif argv[:1] == ["shell"]:
        cmd = argv[1:]
        if cmd == ["dumpsys", "battery"]:
            battery()
        elif cmd == ["dumpsys", "diskstats"]:
            diskstats()
        elif cmd[:3] == ["df", "-h", "/sdcard"]:
            df()
        elif cmd[:2] == ["pm", "list"]:
            packages("-3" in cmd)
        elif cmd[:2] == ["am", "start"]:
            print("Starting: Intent { %s }" % " ".join(cmd[2:]))
        elif cmd[:2] == ["monkey", "-p"]:
            print("Events injected: 1")
        elif cmd[:1] == ["getprop"]:
            getprop(cmd[1] if len(cmd) > 1 else "")
        elif cmd[:2] == ["dumpsys", "display"]:
            display()
        elif cmd[:1] == ["ls"] and "-lR" in cmd:
            ls_recursive([a for a in cmd[1:] if not a.startswith("-")])
        elif cmd[:2] == ["content", "query"]:
            return content_query(cmd[2:])
        elif cmd[:2] == ["svc", "usb"]:
            base = phone_dir()
            base = base if base is not None else Path(os.devnull)
            if cmd[2:3] == ["setFunctions"]:
                if (base / "refuse-usb-tether").is_file():
                    sys.stderr.write("setFunctions failed: operation not permitted\n")
                    return 1
                print("rndis")
            elif cmd[2:3] == ["getFunctions"]:
                print("none" if (base / "usb-tether-off").is_file() else "rndis")
        elif cmd[:1] == ["screenrecord"]:
            print("Recording started; use Ctrl-C to stop")
        elif cmd[:2] == ["input", "tap"]:
            print("tapped")
        # anything else is an honest no-answer, not a guess about hardware
    return 0


if __name__ == "__main__":
    sys.exit(main())
