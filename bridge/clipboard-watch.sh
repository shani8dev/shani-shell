#!/bin/sh
# clipboard-watch — the wl-paste watcher that feeds cliphist, with encryption.
#
# Normal:  wl-paste --watch cliphist store
# Encrypted: wl-paste --watch bridge/clipboard-watch.sh
# The script reads each new clipboard value on stdin and stores it through
# clipboard-crypto.py wrap (which decrypts the DB, runs cliphist store,
# re-encrypts). When encryption is off it calls cliphist directly.
set -e
TOOL=$(dirname "$0")/clipboard-crypto.py
if [ -x "$TOOL" ] && python3 "$TOOL" status 2>/dev/null | grep -q '"encrypted": true'; then
    exec python3 "$TOOL" wrap store
else
    exec cliphist store
fi
