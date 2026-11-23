#!/bin/sh
# crontab stand-in for the suite: keep the person's entries in a file, answer
# -l / -r and accept a new list on stdin. The Services bridge is pointed here
# with SHANI_CRONTAB so the CRUD checks can read back what was really written.
F=${SHANI_CRONTAB_FILE:-/tmp/fake-crontab}
case "$1" in
    -l) [ -f "$F" ] && cat "$F"; exit 0 ;;
    -r) rm -f "$F"; exit 0 ;;
    -) cat > "$F"; exit 0 ;;
    *) echo "usage: fake-crontab.sh -l|-r|-"; exit 2 ;;
esac
