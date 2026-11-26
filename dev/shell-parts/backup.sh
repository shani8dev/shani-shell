# sourced by dev/shell-test.sh: sh dev/check.sh shell=backup
# Every Backup flow against the stand-in: home snapshots (browse, restore a
# file), the other drive (back up now, restore, open in Files), btrfs snapshots
# (create, delete), the daily switch and time, then empty states and an error.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
STATE=/tmp/shani-backup-fake.json
CALLS=/tmp/shani-backup-calls.log
click() { timeout 20 python3 "$A11Y" press "$1" >/dev/null 2>&1; }
seen()  { timeout 20 python3 "$A11Y" find "$1" >/dev/null 2>&1; }

# ---- seeding: the stand-in's real --json state, plus files inside a snapshot ----
rm -f "$CALLS"
cat > "$STATE" <<'JSON'
{"repository":"/run/media/root/USB","reachable":true,"set_up":true,
 "schedule":{"on":true,"time":"21:15"},
 "backups":[{"id":"ab12cd34","time":"2026-11-26T21:15:03+05:30","paths":["/root"],"size":12345}],
 "home_snapshots":[{"name":"daily-2026-11-26","path":"/home/.snapshots/root/daily-2026-11-26","whole":false},
                   {"name":"manual-2026-11-25_10-00-00","path":"/home/.snapshots/root/manual-2026-11-25_10-00-00","whole":false}],
 "snapshots":["/home/.snapshots/root/daily-2026-11-26"],"error":null}
JSON
mkdir -p /home/.snapshots/root/daily-2026-11-26 /tmp/backup-restore /tmp/backup-restore2
printf 'home note from yesterday\n' > /home/.snapshots/root/daily-2026-11-26/notes.txt
printf 'the file now\n' > /tmp/backup-restore/notes.txt

ipc backupClose; sleep 0.4
ipc backupOpen
waitfor "d['backupShown'] and d['backupAvailable'] and d['backupHomeCount'] == 2 and d['backupTab'] == 'home'" 8 \
    && result backup-panel-lists-home-snapshots PASS "$(q "['backupHomeCount'], d['backupVersions']")" \
    || result backup-panel-lists-home-snapshots FAIL "$(q "['backupShown'], d['backupAvailable'], d['backupHomeCount'], d['backupTab']")"
shot backup-home-tab 0.5

# ---- home snapshots: a snapshot taken now, and a file restored from one --------
click "button:^Take a snapshot now$"
waitfor "d['backupLastAction'] == 'home-snapshot' and d['backupHomeCount'] == 3" 6 \
    && result backup-home-snapshot-now PASS "$(grep -c 'home snapshot --json' "$CALLS")" \
    || result backup-home-snapshot-now FAIL "$(q "['backupLastAction'], d['backupHomeCount']")"
grep -q 'home snapshot --json' "$CALLS" || result backup-home-snapshot-command FAIL "$(tail -4 "$CALLS")"

click "button:^Restore a file from the snapshot"
waitfor "d['pickerShown'] and d['pickerPath'] == '/home/.snapshots/root/daily-2026-11-26'" 6 \
    && result backup-restore-file-picker PASS "$(q "['pickerPath']")" \
    || result backup-restore-file-picker FAIL "$(q "['pickerShown'], d['pickerPath']")"
ipc filePickerSelect /home/.snapshots/root/daily-2026-11-26/notes.txt
ipc filePickerAccept
waitfor "d['pickerShown'] and d['pickerPath'] != '/home/.snapshots/root/daily-2026-11-26'" 6
ipc filePickerGo /tmp/backup-restore
sleep 0.8
ipc filePickerAccept
waitfor "d['backupLastAction'] == 'copy-from-snapshot'" 8 \
    && result backup-restores-file-from-snapshot PASS "$(q "['backupNote']")" \
    || result backup-restores-file-from-snapshot FAIL "$(q "['backupLastAction'], d['backupError']")"
[ -s '/tmp/backup-restore/notes (2).txt' ] \
    && grep -q 'home note from yesterday' '/tmp/backup-restore/notes (2).txt' \
    && result backup-restore-keeps-current-file PASS \
    || result backup-restore-keeps-current-file FAIL "$(ls /tmp/backup-restore 2>&1)"

# ---- open a snapshot in Files --------------------------------------------------
click "button:^Browse the snapshot"
waitfor "d['filesShown'] and d['filesPath'] == '/home/.snapshots/root/daily-2026-11-26'" 6 \
    && result backup-browse-snapshot-in-files PASS "$(q "['filesPath']")" \
    || result backup-browse-snapshot-in-files FAIL "$(q "['filesShown'], d['filesPath']")"
ipc filesClose
ipc backupOpen; sleep 0.5

# ---- the other drive: back up now with progress -------------------------------
ipc backupTab backups
waitfor "d['backupTab'] == 'backups' and d['backupCount'] == 1 and d['backupDriveSetUp']" 6 \
    && result backup-panel-lists-drive-backups PASS "$(q "['backupCount'], d['backupRepository']")" \
    || result backup-panel-lists-drive-backups FAIL "$(q "['backupTab'], d['backupCount'], d['backupDriveSetUp']")"
shot backup-drive-tab 0.5
click "button:^Back up now to the backup drive$"
waitfor "not d['backupRunning'] and d['backupLastAction'] == 'backup'" 8 \
    && result backup-now-finishes PASS "$(q "['backupNote']")" \
    || result backup-now-finishes FAIL "$(q "['backupRunning'], d['backupError']")"
[ "$(q "['backupPeakProgress']")" = 100 ] \
    && result backup-now-shows-progress PASS || result backup-now-shows-progress FAIL "$(q "['backupPeakProgress']")"
grep -q '^backup$' "$CALLS" \
    && result backup-now-runs-command PASS "$(grep -c '^backup$' "$CALLS")" \
    || result backup-now-runs-command FAIL "$(tail -6 "$CALLS")"

# ---- open the backup drive in Files -------------------------------------------
click "button:^Open the backup drive in Files$"
waitfor "d['filesShown'] and d['filesPath'] == '/run/media/root/USB'" 6 \
    && result backup-open-drive-in-files PASS "$(q "['filesPath']")" \
    || result backup-open-drive-in-files FAIL "$(q "['filesShown'], d['filesPath']")"
ipc filesClose
ipc backupOpen; sleep 0.5

# ---- restore a whole backup into a chosen folder, confirmed -------------------
click "button:^Pick the backup ab12cd34 to restore$"
waitfor "d['backupPick'] == 'ab12cd34'" 4 || result backup-pick-backup FAIL "$(q "['backupPick']")"
click "button:^Choose where to restore the backup$"
waitfor "d['pickerShown']" 6
ipc filePickerGo /tmp/backup-restore2
sleep 0.8
ipc filePickerAccept
waitfor "d['pickerShown'] == False" 5
click "button:^Restore the chosen backup into the chosen folder$"
sleep 0.4
click "button:^Restore the chosen backup into the chosen folder$"
waitfor "d['backupLastAction'] == 'restore' and d['backupLastTarget'] == '/tmp/backup-restore2'" 8 \
    && result backup-restore-confirmed PASS "$(q "['backupNote']")" \
    || result backup-restore-confirmed FAIL "$(q "['backupLastAction'], d['backupLastTarget'], d['backupError']")"
grep -q 'restore /tmp/backup-restore2 --snapshot ab12cd34 --json' "$CALLS" \
    && result backup-restore-runs-command PASS || result backup-restore-runs-command FAIL "$(tail -6 "$CALLS")"
shot backup-restore-done 0.4

# ---- snapshots: create, delete, the daily switch and its time -----------------
ipc backupTab snapshots
waitfor "d['backupTab'] == 'snapshots'" 5 || result backup-snapshots-tab FAIL "$(q "['backupTab']")"
seen "Before each update, a snapshot" \
    && result backup-preupdate-explained PASS || result backup-preupdate-explained FAIL "no plain-words note"
click "check box:^Back up every day$"
waitfor "not d['backupScheduleOn']" 6 && result backup-schedule-off PASS || result backup-schedule-off FAIL "$(q "['backupScheduleOn']")"
click "check box:^Back up every day$"
waitfor "d['backupScheduleOn']" 6 && result backup-schedule-on PASS || result backup-schedule-on FAIL "$(q "['backupScheduleOn']")"
click "radio button:^Evening · 18:00$"
waitfor "d['backupScheduleTime'] == '18:00'" 6 && result backup-schedule-time-pick PASS || result backup-schedule-time-pick FAIL "$(q "['backupScheduleTime']")"
grep -q 'schedule --at 18:00' "$CALLS" && grep -q 'schedule --disable' "$CALLS" && grep -q 'schedule --enable' "$CALLS" \
    && result backup-schedule-commands PASS || result backup-schedule-commands FAIL "$(grep '^schedule' "$CALLS" | tail -5)"

click "button:^Create a snapshot of the chosen folder$"
waitfor "d['backupLastAction'] == 'snapshot-create' and d['backupSnapCount'] == 2" 6 \
    && result backup-snapshot-create PASS "$(q "['backupLastPath']")" \
    || result backup-snapshot-create FAIL "$(q "['backupLastAction'], d['backupSnapCount'], d['backupError']")"
grep -q 'snapshot create / /home/.snapshots/manual-' "$CALLS" \
    && result backup-snapshot-create-command PASS || result backup-snapshot-create-command FAIL "$(tail -6 "$CALLS")"
shot backup-snapshots-tab 0.5
click "button:^Delete the snapshot daily-2026-11-26$"
sleep 0.4
click "button:^Delete the snapshot daily-2026-11-26$"
waitfor "d['backupLastAction'] == 'snapshot-delete' and d['backupSnapCount'] == 1" 6 \
    && result backup-snapshot-delete-confirmed PASS || result backup-snapshot-delete-confirmed FAIL "$(q "['backupLastAction'], d['backupSnapCount'], d['backupError']")"

# ---- empty states and an error, in plain words --------------------------------
cat > "$STATE" <<'JSON'
{"repository":"","reachable":false,"set_up":false,"schedule":{"on":false,"time":"12:30"},
 "backups":[],"home_snapshots":[],"snapshots":[],"error":null}
JSON
ipc backupClose; sleep 0.4; ipc backupOpen
waitfor "d['backupHomeCount'] == 0 and d['backupCount'] == 0 and not d['backupDriveSetUp']" 6 \
    && result backup-empty-state PASS || result backup-empty-state FAIL "$(q "['backupHomeCount'], d['backupCount']")"
ipc backupTab home
seen "No earlier versions yet" && result backup-empty-home-words PASS || result backup-empty-home-words FAIL
ipc backupTab backups
seen "No backup drive set up" && result backup-empty-drive-words PASS || result backup-empty-drive-words FAIL
shot backup-empty 0.4
cat > "$STATE" <<'JSON'
{"repository":"/run/media/root/USB","reachable":true,"set_up":true,
 "schedule":{"on":true,"time":"21:15"},
 "backups":[{"id":"ab12cd34","time":"2026-11-26T21:15:03+05:30","paths":["/root"],"size":1}],
 "home_snapshots":[{"name":"daily-2026-11-26","path":"/home/.snapshots/root/daily-2026-11-26","whole":false}],
 "snapshots":[],"error":"the backup drive is asleep"}
JSON
ipc backupClose; sleep 0.4; ipc backupOpen
waitfor "d['backupError'] != ''" 6 && result backup-error-in-plain-words PASS "$(q "['backupError']")" \
    || result backup-error-in-plain-words FAIL "$(q "['backupError']")"
ipc backupClose
rm -f "$STATE" "$CALLS"
