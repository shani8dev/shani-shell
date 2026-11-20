#!/bin/sh
# shani-admin.py, for the shell suite: what pkexec would run is recorded instead
# (/tmp/admin-log: "<command> <the JSON request>"), and it answers ok.
# The real one runs as root in dev/admin-test.sh.
read -r req
echo "$1 $req" >> /tmp/admin-log
echo '{"ok": true}'
