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
    ("Lens — screen OCR & QR", ["tesseract", "zbarimg", "grim", "slurp"],
     "tesseract zbar grim slurp", "tesseract-ocr zbar-tools grim slurp"),
    ("Color picker", ["wl-copy", "notify-send"],
     "wl-clipboard libnotify", "wl-clipboard libnotify-bin"),
    ("App launching", ["gtk-launch", "xdg-open", "xdg-email", "gio"],
     "gtk3 xdg-utils glib2", "gtk3 xdg-utils libglib2.0-bin"),
    ("Systemd unit management", ["kill", "systemctl"],
     "systemd", "systemd"),
    ("GNOME network displays", ["gnome-network-displays"],
     "gnome-network-displays", "gnome-network-displays"),
    ("Printing GUI", ["system-config-printer"],
     "system-config-printer", "system-config-printer"),
    ("Audio & microphone", ["wpctl", "pactl", "pw-record", "pw-metadata", "pipewire"],
     "wireplumber pulseaudio-alsa pipewire", "wireplumber pulseaudio-utils pipewire"),
    ("Bluetooth", ["bluetoothctl", "gdbus", "kdeconnect-cli"],
     "bluez-utils glib2 kdeconnect", "bluez-utils libglib2.0-bin kdeconnect"),
    ("Screen recording", ["wf-recorder", "grim", "slurp"],
     "wf-recorder grim slurp", "wf-recorder grim slurp"),
    ("Screen ruler / capture", ["grim", "slurp", "wl-copy"],
     "grim slurp wl-clipboard", "grim slurp wl-clipboard"),
    ("Shell settings (gsettings)", ["gsettings"],
     "glib2", "libglib2.0-bin"),
    ("Chronoa bridge / D-Bus", ["dbus-send", "gdbus"],
     "dbus", "libglib2.0-bin"),
    ("Notifications", ["notify-send"],
     "libnotify", "libnotify-bin"),
    ("Clipboard", ["wl-copy", "wl-paste", "cliphist"],
     "wl-clipboard cliphist", "wl-clipboard cliphist"),
    ("Network & Wi-Fi", ["nmcli", "tailscale", "nm-connection-editor", "rfkill"],
     "networkmanager tailscale network-manager-applet iproute2", "network-manager tailscale network-manager-gnome iproute2"),
    ("Screen sharing", ["sunshine", "wl-mirror"],
     "sunshine wl-mirror", "sunshine wl-mirror"),
    ("Power & battery", ["upower", "brightnessctl"],
     "upower brightnessctl", "upower brightnessctl"),
    ("Night light", ["wlsunset"],
     "wlsunset", "wlsunset"),
    ("Display", ["niri", "ddcutil", "switcherooctl", "xdotool"],
     "niri ddcutil switcheroo-control", "niri ddcutil switcheroo-control"),
    ("Keyboard / input", ["wtype", "fcitx5", "fcitx5-remote", "fcitx5-configtool"],
     "wtype fcitx5", "wtype fcitx5"),
    ("Fingerprint", ["fprintd-enroll", "fprintd-list"],
     "fprintd", "fprintd"),
    ("Printing", ["system-config-printer", "udisksctl"],
     "system-config-printer udisks2", "system-config-printer udisks2"),
    ("Accessibility", ["orca", "spd-say", "monitor-sensor"],
     "orca speech-dispatcher iio-sensor-proxy", "orca speech-dispatcher iio-sensor-proxy"),
    ("Security keys / smartcards", ["fprintd-enroll", "malcontent-control"],
     "fprintd malcontent", "fprintd malcontent"),
    ("Firmware", ["fwupdmgr"],
     "fwupd", "fwupd"),
    ("GPU / graphics", ["switcherooctl", "glxinfo"],
     "switcheroo-control mesa-utils", "switcheroo-control mesa-utils"),
    ("Storage", ["lsblk", "udisksctl", "btrfs"],
     "util-linux udisks2 btrfs-progs", "util-linux udisks2 btrfs-progs"),
    ("Cassini (system manager)", ["shani-cassini", "gdbus"],
     "shani-cassini", "shani-cassini"),
    ("Chronoa (AI assistant)", ["python3", "shani-chronoa"],
     "python shani-chronoa", "python3 shani-chronoa"),
    ("Flatpak", ["flatpak", "gtk-launch"],
     "flatpak gtk3", "flatpak gtk3"),
    ("Color tools", ["pdftoppm", "rg", "fd", "qrencode", "plocate"],
     "poppler fd ripgrep qrencode plocate", "poppler-utils fd-find ripgrep qrencode plocate"),
    ("Misc utilities", ["cliphist", "satty", "vnstat"],
     "cliphist satty vnstat", "cliphist satty vnstat"),
    ("Calendar", ["gnome-calendar", "localsearch"],
     "gnome-calendar localsearch", "gnome-calendar localsearch"),
    ("Screen casting", ["gnome-network-displays", "shani-deploy"],
     "gnome-network-displays shani-deploy", "gnome-network-displays shani-deploy"),
    ("Privilege escalation", ["pkexec", "systemctl"],
     "polkit systemd", "policykit-1 systemd"),
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
    return "install " + arch_pkg


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
