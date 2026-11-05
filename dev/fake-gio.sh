#!/bin/sh
# Stands in for gio's mount and open (no gvfs devices in a container): `mount -li`
# lists a camera, a phone and an iPhone as gvfs shows them, unmounted until
# `mount ROOT`; every call goes to ${FAKE_GIO_LOG:-/tmp/gio-log}.
echo "$*" >> "${FAKE_GIO_LOG:-/tmp/gio-log}"
m=${FAKE_GIO_MOUNTED:-/tmp/gio-mounted}
case "$1" in
mount)
    if [ "$2" = -li ]; then
        cat <<'L'
Drive(0): Samsung SSD 980
  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)
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
        [ -f "$m" ] && sed 's/^/Mount(0): x -> /' "$m"
    else
        echo "$2" >> "$m"
    fi ;;
open) ;;
*) exit 1 ;;
esac
exit 0
