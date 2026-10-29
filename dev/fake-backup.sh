#!/bin/sh
# shani-backup for the suite: the --json answers the shell reads, and a record
# of what was opened (/tmp/backup-opened)
today=$(date +%F)
case "$1 $2" in
  "home list") printf '{"ok": true, "user": "root", "snapshots": [{"name": "daily-%s", "path": "/x", "whole": true}, {"name": "daily-2026-01-02", "path": "/y", "whole": true}]}\n' "$today" ;;
  "backups --json") printf '{"ok": true, "repository": "/run/media/root/USB", "reachable": true, "set_up": true, "schedule": {"on": true, "time": "21:15"}, "backups": [{"id": "ab12cd34", "time": "%sT21:15:03+05:30", "paths": [], "size": 1}]}\n' "$today" ;;
  open*) echo "$*" >> /tmp/backup-opened ;;
  "backup --json") echo "backup" >> /tmp/backup-opened; printf '{"ok": true, "snapshot": "ab12cd34"}\n' ;;
  *) exit 64 ;;
esac
