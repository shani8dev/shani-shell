#!/bin/sh
# Stands in for NUT's `upsc` (no UPS in a container): with /tmp/fake-ups present,
# one UPS called "myups" whose variables are that file's "key: value" lines -
# the suite rewrites it to cut and restore the power. Without the file, no UPS.
[ -f /tmp/fake-ups ] || exit 1
case "$1" in
    -l) echo myups ;;
    myups@*) cat /tmp/fake-ups ;;
    *) exit 1 ;;
esac
