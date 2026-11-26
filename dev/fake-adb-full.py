#!/usr/bin/env python3
"""adb stand-in for the Devices window's live check (dev/shell-parts/devices.sh).

Answers exactly the verbs the phone panel asks, and nothing else — every call
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

Env:
  SHANI_ADB_LOG     call log (default /tmp/fake-adb-calls)
  SHANI_ADB_STATE   scratch dir for push/pull (default /tmp/fake-adb-state)
"""

from __future__ import annotations

import os
import shutil
import struct
import sys
import zlib
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
        print("%s: 1 file pushed" % src.name)
    elif argv[:1] == ["pull"] and len(argv) >= 3:
        target = Path(argv[2])
        target.parent.mkdir(parents=True, exist_ok=True)
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
        elif cmd[:1] == ["screenrecord"]:
            print("Recording started; use Ctrl-C to stop")
        elif cmd[:2] == ["input", "tap"]:
            print("tapped")
        # anything else is an honest no-answer, not a guess about hardware
    return 0


if __name__ == "__main__":
    sys.exit(main())
