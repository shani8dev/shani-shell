#!/bin/sh
# Stands in for libcamera's `cam` in the dev session (no camera in a container):
# `-l` lists one camera; a capture writes eight 64x48 PPM frames where -F says
# ('#' -> the frame number), so the shell's still path runs for real.
case " $* " in
*" -l "*) echo "Available cameras:"; echo "1: 'Test Camera' (/fake/camera)"; exit 0 ;;
esac
out=""
while [ $# -gt 0 ]; do [ "$1" = -F ] && out="$2"; shift; done
[ -n "$out" ] || exit 2
for i in 0 1 2 3 4 5 6 7; do
    f=$(echo "$out" | sed "s/#/cam0-stream0-00000$i/")
    { printf 'P6\n# fake\n64 48\n255\n'; python3 -c "import sys; sys.stdout.buffer.write(bytes([200, 60 + $i * 10, 40]) * (64 * 48))"; } > "$f"
done
