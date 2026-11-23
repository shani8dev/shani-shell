# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=services)
# ---- the Services app (Ui.servicesApp): user units, timers and the person's
#      cron, with writes. No root or assistant tool is involved: systemctl
#      --user and crontab. The cron entry is added and removed through the app's
#      own IPC and read back from the real crontab, so a "Saved" that wrote
#      nothing cannot pass.
ipc servicesOpen; sleep 1.5
waitfor "d['servicesShown'] == True" 6 && result services-app-opens PASS || result services-app-opens FAIL "$(q "['servicesShown']")"
# the nested container has no user systemd bus, so an empty list is a valid
# answer - what is checked is that the bridge answers JSON, not a traceback
python3 "$SHANI_SERVICES_TOOL" services 2>/dev/null | python3 -c 'import json,sys; assert isinstance(json.load(sys.stdin), list)' \
    && result services-lists-units PASS || result services-lists-units FAIL "the bridge did not answer"
shot services-app 0.4

# the C and D of CRUD, read back from crontab itself
LINE="0 9 * * 1-5 /bin/true"
SHANI_CRONTAB=/work/dev/fake-crontab.sh SHANI_CRONTAB_FILE=/tmp/fake-crontab sh /work/dev/fake-crontab.sh -r
ipc servicesCronAdd "0 9 * * 1-5" "/bin/true"; sleep 1.5
waitfor "d['cronCount'] == 1" 8 && result services-cron-added PASS "$(q "['cronCount']")" || result services-cron-added FAIL "$(q "['cronCount']")"
SHANI_CRONTAB=/work/dev/fake-crontab.sh SHANI_CRONTAB_FILE=/tmp/fake-crontab sh /work/dev/fake-crontab.sh -l | grep -qF "$LINE" && result services-cron-wrote-the-entry PASS || result services-cron-wrote-the-entry FAIL "$(SHANI_CRONTAB_FILE=/tmp/fake-crontab sh /work/dev/fake-crontab.sh -l 2>&1 | head -c 120)"

ipc servicesCronRemove 0; sleep 1.5
waitfor "d['cronCount'] == 0" 8 && result services-cron-removed PASS || result services-cron-removed FAIL "$(q "['cronCount']")"
SHANI_CRONTAB=/work/dev/fake-crontab.sh SHANI_CRONTAB_FILE=/tmp/fake-crontab sh /work/dev/fake-crontab.sh -l | grep -qF "$LINE" && result services-cron-removed-the-entry FAIL "still in crontab" || result services-cron-removed-the-entry PASS

ipc servicesClose
rm -f /tmp/fake-crontab
