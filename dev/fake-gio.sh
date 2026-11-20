#!/bin/sh
# Stands in for gio's mount, info and open (no gvfs or udisks in a container), in
# gio's own layout: `mount -li` lists a camera, a phone and an iPhone as gvfs
# shows them, a USB stick on its drive and a laptop's other partition - each
# unmounted until mounted (`mount ROOT`, `mount -d DEV`), then with its Mount
# under it. A mounted one's files are /tmp/fake-gvfs/<name> (`info` says so, as
# gvfsd-fuse's local path). smb://…/locked/ asks for a login: the password "pw"
# opens it, and is the encrypted /dev/sdc1's passphrase. Every call goes to ${FAKE_GIO_LOG:-/tmp/gio-log}.
echo "$*" >> "${FAKE_GIO_LOG:-/tmp/gio-log}"
m=${FAKE_GIO_MOUNTED:-/tmp/gio-mounted}
G=${FAKE_GVFS:-/tmp/fake-gvfs}
touch "$m"
local_of() { printf '%s/%s' "$G" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._\n-' '_')"; }
mounted() { grep -qxF "$1" "$m"; }
mounts_of() {   # ROOT: its Mount lines, two spaces deeper than INDENT ($2)
    mounted "$1" || return 0
    printf '%sMount(0): %s -> %s\n%s  default_location=%s\n%s  can_unmount=1\n%s  can_eject=%s\n' \
        "$2" "$3" "$4" "$2" "$4" "$2" "$2" "${5:-0}"
}
case "$1" in
mount)
    case "$2" in
    -li)
        cat <<'L'
Drive(0): Samsung SSD 980
  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)
  ids:
   unix-device: '/dev/nvme0n1'
  is_removable=0
  can_eject=0
  Volume(0): Data
    Type: GProxyVolume (GProxyVolumeMonitorUDisks2)
    ids:
     class: 'device'
     unix-device: '/dev/nvme0n1p4'
    can_mount=1
    can_eject=0
L
        mounts_of /dev/nvme0n1p4 "    " Data "file://$(local_of /dev/nvme0n1p4)"
        cat <<'L'
Drive(1): SanDisk Cruzer Blade
  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)
  ids:
   unix-device: '/dev/sdb'
  is_removable=1
  can_eject=1
  Volume(0): STICK
    Type: GProxyVolume (GProxyVolumeMonitorUDisks2)
    ids:
     class: 'device'
     unix-device: '/dev/sdb1'
    can_mount=1
    can_eject=1
L
        mounts_of /dev/sdb1 "    " STICK "file://$(local_of /dev/sdb1)" 1
        cat <<'L'
Drive(2): Kingston DataTraveler
  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)
  ids:
   unix-device: '/dev/sdc'
  is_removable=1
  can_eject=1
  Volume(0): Locked stick
    Type: GProxyVolume (GProxyVolumeMonitorUDisks2)
    ids:
     class: 'device'
     unix-device: '/dev/sdc1'
    can_mount=1
    can_eject=1
L
        mounts_of /dev/sdc1 "    " "Locked stick" "file://$(local_of /dev/sdc1)" 1
        cat <<'L'
Volume(0): Canon Digital Camera
  Type: GProxyVolume (GProxyVolumeMonitorGPhoto2)
  activation_root=gphoto2://Canon_Inc._Canon_Digital_Camera/
Volume(1): Pixel 8
  Type: GProxyVolume (GProxyVolumeMonitorMTP)
  activation_root=mtp://Google_Pixel_8_3A1B/
Volume(2): iPhone
  Type: GProxyVolume (GProxyVolumeMonitorAfc)
  activation_root=afc://00008110/
L
        for r in gphoto2://Canon_Inc._Canon_Digital_Camera/ mtp://Google_Pixel_8_3A1B/ afc://00008110/; do
            mounts_of "$r" "" x "$r"
        done
        # servers connected to: a mount of their own, no volume
        grep -E '^(smb|sftp|ftp|dav|davs|nfs)://' "$m" | while read -r r; do mounts_of "$r" "" "$r" "$r"; done ;;
    -d)
        # /dev/sdc1 is LUKS: gio asks for the passphrase on stdin; "pw" opens it
        if [ "$3" = /dev/sdc1 ]; then
            read -r pass
            [ "$pass" = pw ] || { echo "gio: /dev/sdc1: Error unlocking /dev/sdc1: Failed to activate device: Operation not permitted" >&2; exit 2; }
        fi
        echo "$3" >> "$m"; mkdir -p "$(local_of "$3")" ;;
    -u|-e)
        p=$3; [ "${p#/}" = "$p" ] || for r in $(cat "$m"); do [ "$(local_of "$r")" = "$p" ] && p=$r; done
        grep -vxF "$p" "$m" > "$m.new"; mv "$m.new" "$m" ;;
    *)
        case "$2" in
        *locked*)
            read -r user; read -r domain; read -r pass
            [ "$pass" = pw ] || { echo "gio: $2: Permission denied" >&2; exit 2; } ;;
        esac
        echo "$2" >> "$m"; mkdir -p "$(local_of "$2")" ;;
    esac ;;
info)
    eval "u=\${$#}"
    if mounted "$u"; then echo "display name: x"; echo "local path: $(local_of "$u")"; fi ;;
list)
    # network:// - what gvfs's dnssd, wsdd and smb browsers find
    case "$*" in *network:*)
        printf 'dnssd-domain-local-NAS._smb._tcp\t0\t(shortcut)\tstandard::display-name=Office NAS standard::target-uri=smb://nas.local/\n'
        printf 'dnssd-domain-local-pi._sftp-ssh._tcp\t0\t(shortcut)\tstandard::display-name=pi standard::target-uri=sftp://pi.local/\n'
        printf 'dnssd-domain-local-media._nfs._tcp\t0\t(shortcut)\tstandard::display-name=media standard::target-uri=nfs://media.local/export\n'
        printf 'smb-root\t0\t(shortcut)\tstandard::display-name=Windows Network standard::target-uri=smb:///\n' ;;
    esac ;;
open) ;;
*) exit 1 ;;
esac
exit 0
