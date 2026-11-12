#!/bin/sh
# Stands in for `udevadm monitor --udev --property` (no udev in a container):
# what the suite writes into the FIFO /tmp/udev-events - the recordings in
# dev/udev/ - comes out as udev's own events would. Blocks on the FIFO between
# writes, like the real monitor on its socket.
f=${SHANI_UDEV_FIFO:-/tmp/udev-events}
[ -p "$f" ] || mkfifo "$f"
echo "monitor will print the received events for:"
echo "UDEV - the event which udev sends out after rule processing"
echo
# read with the shell's own `read`, never a `cat` child: when the shell stops,
# plugwatch takes this script with it (PDEATHSIG), but a `cat` would live on, an
# orphan holding the FIFO open, and swallow the next event written
while :; do
    while IFS= read -r line; do printf '%s\n' "$line"; done < "$f"
done
