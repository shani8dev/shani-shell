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
while :; do cat "$f"; done
