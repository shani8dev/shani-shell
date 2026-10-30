#!/usr/bin/env python3
"""shani-doctor — self-check the tools the shani shell needs.

For every surface/feature, lists the external binaries it calls, marks each
present/missing, and prints the distro install command for anything missing.

Modelled on `voltkit doctor`: "tells you exactly what's missing and the
command to install it."

Exit 0 if every needed tool is present, 1 otherwise.
"""
from __future__ import annotations

import os
import shutil
import sys


# (feature, tools needed, Arch package(s), Debian/Ubuntu package(s))
FEATURES = [
    ("Lens — screen OCR & QR",
     ["tesseract", "zbarimg", "grim", "slurp"],
     "tesseract zbar grim slurp",
     "tesseract-ocr zbar-tools grim slurp"),
    ("Color picker",
     ["wl-copy", "notify-send"],
     "wl-clipboard libnotify",
     "wl-clipboard libnotify-bin"),
    ("Audio & microphone",
     ["wpctl", "pactl"],
     "wireplumber pulseaudio-alsa",
     "wireplumber pulseaudio-utils"),
    ("Bluetooth",
     ["bluetoothctl"],
     "bluez-utils",
     "bluez-utils"),
    ("Screen recording",
     ["wf-recorder", "grim", "slurp"],
     "wf-recorder grim slurp",
     "wf-recorder grim slurp"),
    ("Shell settings (gsettings)",
     ["gsettings"],
     "glib2",
     "libglib2.0-bin"),
    ("Chronoa bridge / D-Bus",
     ["dbus-send", "gdbus"],
     "dbus",
     "libglib2.0-bin"),
    ("Notifications",
     ["notify-send"],
     "libnotify",
     "libnotify-bin"),
    ("Clipboard",
     ["wl-copy", "wl-paste"],
     "wl-clipboard",
     "wl-clipboard"),
    ("Network & Wi-Fi",
     ["nmcli"],
     "networkmanager",
     "network-manager"),
    ("Power & battery",
     ["upower"],
     "upower",
     "upower"),
]


def distro_id():
    try:
        with open("/etc/os-release") as f:
            info = {}
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    info[k.strip()] = v.strip().strip('"')
            return info.get("ID", "").lower()
    except OSError:
        return ""


def install_cmd(distro, arch_pkg, deb_pkg):
    arch_family = {"arch", "endeavouros", "manjaro"}
    deb_family = {"ubuntu", "debian", "linuxmint", "pop", "zorin", "raspbian"}
    if distro in arch_family:
        return "sudo pacman -S " + arch_pkg
    if distro in deb_family:
        return "sudo apt install " + deb_pkg
    return "install " + arch_pkg  # generic fallback


def main():
    distro = distro_id()
    missing_any = False
    print("shani-doctor: tools the shell needs")
    print("=" * 56)
    for name, tools, arch_pkg, deb_pkg in FEATURES:
        print("\n" + name)
        feature_missing = False
        for tool in tools:
            present = shutil.which(tool) is not None
            if not present:
                missing_any = True
                feature_missing = True
            print("  [{}] {}".format("OK " if present else "MISSING", tool))
        if feature_missing:
            print("    -> {}".format(install_cmd(distro, arch_pkg, deb_pkg)))
    print()
    if missing_any:
        print("Some tools are missing. Install them, then restart the shell.")
        return 1
    print("All checked tools are present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
